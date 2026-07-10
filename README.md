# platform-gitops

The dedicated GitOps repo for cluster **platform add-ons** — everything the microservices need to run except the microservices themselves (those live in `../deployment`). ArgoCD, bootstrapped by `../kubernetes-infrastructure`'s Terraform, syncs *only* from this repo's `bootstrap/root` path; from there this repo owns every add-on as an app-of-apps.

## How it's wired up

`kubernetes-infrastructure/terraform/kubernetes/bootstrap.tf` creates exactly one ArgoCD `Application` pointed at this repo — `platform-root`, sourced from `bootstrap/root`. That's this repo's single entry point into the cluster: **`bootstrap/root` is what Terraform creates as its one ArgoCD Application, and everything else here hangs off it.**

## Layout

```
bootstrap/root/
  Chart.yaml
  values.yaml               # global.*, secretStores.*, project.*, addons.<name>.*
  templates/
    project.yaml             # ArgoCD AppProject
    applications.yaml        # renders one Application per enabled addon, with sync-wave
platform/<addon>/             # one directory per addon (24 total)
ci/
  global-values.yaml          # CI stand-in for ArgoCD-injected global values
  secret-stores-values.yaml   # extra values only external-secrets-config needs in CI
  render-upstream-charts.sh   # pulls + renders every upstream-chart addon for real CI coverage
.github/workflows/ci.yml
.checkov.yaml
```

`bootstrap/root/templates/applications.yaml` iterates `.Values.addons`, gated by `enabled` and (for cloud-specific addons like `aws-load-balancer-controller`) an `enabledFor: [aws, ...]` list, and renders one ArgoCD `Application` per addon with `argocd.argoproj.io/sync-wave` set from that addon's `syncWave` (ranging from `-20` for the AWS load balancer controller up to `3` for `keycloak-config` — earlier waves are infra-adjacent/CRD-providing, later waves depend on earlier ones being healthy).

## Two addon kinds

Every addon in `bootstrap/root/values.yaml`'s `addons:` map is one of exactly two kinds — this distinction is documented directly in `.github/workflows/ci.yml`'s own header comment, and it shapes almost everything else about how this repo is validated:

1. **Local charts** — referenced by `path:` in `values.yaml`, with a real `Chart.yaml` + `templates/` in `platform/<addon>/`: `storage-class`, `cert-manager-config`, `gateway`, `external-secrets-config`, `monitoring-config`, `postgres-cluster`, `postgres-app-roles`, `keycloak`, `keycloak-config`, `keycloak-operator` (10 total). These hold Kubernetes resources that aren't themselves an upstream Helm release — cluster issuers, the shared Gateway, ExternalSecret/ClusterSecretStore objects, Grafana provisioning/alerting config, the CloudNativePG `Cluster` CR, a Sync-hook Job that creates the app-service PostgreSQL roles from inside the cluster network (`postgres-app-roles` — see its own comment in `bootstrap/root/values.yaml`), the Keycloak `Keycloak`/`KeycloakRealmImport` CRs, and (see below) a fully vendored operator.
2. **Upstream-chart addons** — referenced by `chart:`+`repoURL:`+`targetRevision:` in `values.yaml`, with **only a `values.yaml`** in `platform/<addon>/` (no `Chart.yaml`, no templates): `aws-load-balancer-controller`, `cert-manager`, `gateway-api-crds`, `istio-base`, `istio-cni`, `istiod`, `ztunnel`, `kiali`, `external-dns`, `external-secrets`, `kube-prometheus-stack`, `loki`, `tempo`, `alloy`, `cloudnative-pg` (14 total). ArgoCD pulls the real chart straight from its upstream Helm repo at sync time and uses this repo's `values.yaml` purely as a `valueFiles` overlay (`applications.yaml`'s `sources:`-based branch, a multi-source ArgoCD Application).

## What's actually deployed

- **Ingress/mesh**: Gateway API CRDs, Istio ambient (`istio-base`/`istio-cni`/`istiod`/`ztunnel`), a shared `Gateway` (`platform/gateway`, wildcard + apex TLS cert via cert-manager), and Kiali for mesh observability.
- **Certificates/DNS**: `cert-manager` + `cert-manager-config` (DNS-01 `ClusterIssuer` via Cloudflare), `external-dns` (`sources: [gateway-httproute, service]`, `policy: sync`, shared `txtOwnerId: micro-market` so DNS ownership can hand off cleanly between clouds).
- **Data**: CloudNativePG operator + a local `postgres-cluster` chart (a CR: 2 instances, per-service databases/roles, superuser access disabled) — both disabled since PostgreSQL moved to each cloud's managed service (ADR-9). `postgres-app-roles` is the currently-active piece: a Sync-hook Job that creates/updates the `catalog_svc`/`orders_svc`/`audit_svc` roles, schemas, and grants on that managed server from inside the cluster network, because Terraform's `cyrilgdn/postgresql` provider can't reach the private endpoint from a normal runner (see `plans/2026-07-09-postgres-app-role-job.md`).
- **Identity**: the official Keycloak Operator (vendored, see below) + a `Keycloak` CR + `keycloak-config` (a keycloak-config-cli Sync-hook Job that applies the realm as JSON committed to this repo — independent `microservices-app` client secret, brute-force protection, TOTP for admins, token lifespans, a Kiali OIDC client, dev-only demo users).
- **Secrets**: External Secrets Operator + per-cloud `ClusterSecretStore`s (AWS Secrets Manager / Azure Key Vault / GCP Secret Manager, credentials via each cloud's workload identity — no static cloud credentials stored in the cluster).
- **Observability**: kube-prometheus-stack (Prometheus + Grafana + Alertmanager) + Loki (logs) + Tempo (traces) + Alloy (OTLP receiver, forwarding traces from the Quarkus services' `quarkus-opentelemetry` exporters into Tempo).
- **AWS-only**: `aws-load-balancer-controller` (gated via `enabledFor: [aws]` — the only addon that isn't deployed identically on all three clouds, since it's an AWS-specific controller).

## The `keycloak-operator` story

The Keycloak project deliberately does **not** publish a Helm chart at all — [the official installation docs](https://www.keycloak.org/operator/installation) point to OLM or raw `kubectl apply` of manifests, and `quay.io/keycloak/keycloak-operator` is a plain container image reference, not a Helm OCI chart artifact. `helm template`/`helm show chart` against it fail outright with a chart-vs-image mediatype mismatch — this was found and confirmed by testing, not assumed, and it would have failed to sync in a real cluster too. The one community-maintained chart on ArtifactHub was a single-maintainer v0.0.4 project, judged not worth depending on for this.

Fix: the official CRDs (`keycloaks.k8s.keycloak.org`, `keycloakrealmimports.k8s.keycloak.org`) and RBAC/ServiceAccount/Service/Deployment manifests were vendored from `github.com/keycloak/keycloak-k8s-resources` at the pinned `26.3.1` tag into `platform/keycloak-operator/{crds,templates}` as a proper local chart — CRDs live in Helm's dedicated `crds/` directory (installed as-is, not templated); only the container `resources` block is templated, everything else stays close to upstream. `bootstrap/root/values.yaml`'s `keycloak-operator` entry is `path`-based like every other local chart, not `chart`-based. The vendored Deployment was additionally hardened (upstream ships with zero securityContext): `allowPrivilegeEscalation: false`, all capabilities dropped, seccomp `RuntimeDefault`, plus a dedicated NetworkPolicy — `runAsNonRoot`/`readOnlyRootFilesystem` were deliberately **not** set, because upstream issue `keycloak/keycloak-operator#458` documents `runAsNonRoot` breaking this exact image's startup, and neither could be verified without a live cluster (documented via `checkov.io/skip` annotations on the resource, not guessed).

## CI pipeline (`.github/workflows/ci.yml`)

CI runs on GitHub Actions (migrated from GitLab CI, see
`Sources/plans/2026-07-08-gitlab-to-github-migration.md`). No promote job in
this repo — that's `deployment`'s concern. Jobs:

- `security-scan-gate`: calls the reusable workflow in `devdanielgherasim/micro-market-utilities`. Uses `codeql-languages: actions` since this repo's analyzable code surface is GitHub Actions workflow code, not an application language.
- `helm-lint`: `helm lint` against each of the 10 `LOCAL_CHARTS`, using `ci/global-values.yaml` (plus `ci/secret-stores-values.yaml` for `external-secrets-config`, kept as a separate file because several upstream charts — e.g. cert-manager — have a strict `values.schema.json` that would reject the extra `aws`/`azure`/`gcp` keys if merged into the shared global file).
- `helm-template`: renders the 10 local charts (with `--include-crds`, relevant today only to `keycloak-operator`'s vendored CRDs) into `rendered/local/<addon>/`, then runs **`ci/render-upstream-charts.sh`** — since the 14 upstream-chart addon directories contain no chart to `helm template` directly, this script does what ArgoCD effectively does at sync time: pull each pinned upstream chart from its real Helm repo and render it with this repo's local `values.yaml` on top, into `rendered/upstream/<addon>/`. The addon table inside the script (name/repoURL/chart/version/valuesPath/namespace) is a deliberately hand-maintained mirror of `bootstrap/root/values.yaml`'s `addons:` map — the CI image (`alpine/helm`) has no YAML parser, and this list changes rarely enough that a small maintained table beats adding a parsing dependency. A single addon failing to render doesn't abort the rest of the script, but the job still exits non-zero overall so a real regression isn't silently swallowed.
- `kubeconform` + `checkov` (both depend on `helm-template`): validate everything under `rendered/`. `kubeconform` again uses `-ignore-missing-schemas` plus the `datreeio/CRDs-catalog` source, covering cert-manager/Gateway API/several others; core Kubernetes kinds are always validated strictly.

### `.checkov.yaml`

`rendered/upstream/` (the 14 unmodified third-party charts) is `skip-path`'d as a block — but only after being audited by hand first, not blanket-ignored: a full manual checkov run (334 findings / 3015 passed at the time) confirmed zero `privileged: true` containers anywhere, and that every hostNetwork/hostPID/elevated-capability finding that does fire is structurally required by well-known upstream defaults (`istio-cni-node`'s CNI plugin installation, `ztunnel`'s ambient-mode traffic interception, `kube-prometheus-stack`'s `node-exporter` reading real host metrics) rather than accidental. `rendered/local/` — this repo's own 9 charts — is **not** skipped and is fully scanned; real findings there were fixed directly in the templates (e.g. `keycloak-config`'s sync-hook Job had zero securityContext/resources/NetworkPolicy before this pipeline was built, now has all three). Four `skip-check` IDs remain, each with a documented reason mirroring `../deployment`'s equivalents: `CKV_K8S_43` (digest pinning — chart `targetRevision` pins already give reproducibility), `CKV_K8S_21` (default-namespace false positive — real namespace comes from each Application's `destination.namespace`), `CKV_K8S_35`/`CKV_K8S_40` (secrets-as-env-vars and high-UID, both firing on `keycloak-config`'s sync Job specifically because the `adorsys/keycloak-config-cli` image's entire config interface is env vars with an unknown baked-in file-ownership UID — a deliberate, third-party-image-driven call, not upstream noise passed through).

## Interim state carried over from earlier phases

Bitnami PostgreSQL and Bitnami Keycloak were used as an interim bridge in Phase 2 before Phase 6 replaced them with CloudNativePG and the official Keycloak Operator respectively — both are gone now; what's listed under "What's actually deployed" above is the current, final state, not the interim one.
