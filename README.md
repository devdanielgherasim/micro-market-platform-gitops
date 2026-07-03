# Platform GitOps

Argo CD source of truth for cluster platform add-ons.

Terraform in `kubernetes-infrastructure` bootstraps the cluster connection, installs Argo CD, registers repository credentials, and creates one root `Application` pointing at `bootstrap/root`. This repository then owns platform add-ons through an app-of-apps layout.

## Layout

- `bootstrap/root`: Helm chart that renders the platform `AppProject` and one Argo CD `Application` per add-on.
- `platform/<addon>/values.yaml`: Helm values consumed by Argo CD multi-source applications.
- `platform/<addon>/Chart.yaml`: local charts for Kubernetes resources that are not upstream Helm releases.

## Interim Notes

Phase 2 keeps Bitnami PostgreSQL and Keycloak only as an interim bridge. Phase 6 replaces them with CloudNativePG and the official Keycloak Operator.

Secrets are referenced by name only. Until Phase 4 moves all secret material into cloud secret managers and External Secrets Operator, `kubernetes-infrastructure` keeps bootstrap Kubernetes secrets for Cloudflare, PostgreSQL, Keycloak, Grafana, and application client credentials.
