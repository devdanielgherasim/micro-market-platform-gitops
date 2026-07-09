#!/bin/sh
# Templates every "upstream-chart" addon (referenced in
# bootstrap/root/values.yaml `addons.*` by `chart:`+`repoURL:`, not `path:`)
# against its pinned targetRevision and this repo's local values.yaml
# override, into rendered-upstream/<addon>/.
#
# These addon directories (platform/<addon>/) contain *only* a values.yaml --
# no Chart.yaml, no templates/ -- because ArgoCD pulls the real chart
# straight from the upstream Helm repo at sync time and uses the local
# values.yaml purely as a `valueFiles` overlay (see
# bootstrap/root/templates/applications.yaml, the `sources:`-based branch).
# `helm lint`/`helm template` can't be pointed at these directories directly
# (there's no chart there), so this script does what ArgoCD effectively does:
# pull the pinned upstream chart and render it with the local values file on
# top -- giving CI real coverage of the actual manifests deployed (Prometheus/
# Grafana pod specs, cert-manager controller, Istio control plane, etc.),
# which is where most of the checkov-relevant container security surface
# actually lives.
#
# The addon table below is a deliberate, hand-maintained mirror of
# bootstrap/root/values.yaml `addons.*` (chart/repoURL/targetRevision/
# valuesPath/namespace) rather than parsed out of that file at CI time --
# this repo's CI image (alpine/helm) has no YAML-parsing tool, and the addon
# list changes rarely enough that a small maintained table is simpler and
# more auditable than adding a parser dependency. When an addon is added,
# removed, or version-bumped in bootstrap/root/values.yaml, update the
# matching row here.
#
# Table columns: name repoURL chart version valuesPath namespace
# keycloak-operator is NOT in this table -- it moved to a local chart
# (platform/keycloak-operator, with a real Chart.yaml + crds/ + templates/)
# because the Keycloak maintainers don't publish a Helm chart at all;
# quay.io/keycloak/keycloak-operator is a container image reference, not a
# chart artifact. It's now linted/templated by the main helm-lint/
# helm-template jobs' $LOCAL_CHARTS loop like any other local chart -- see
# that chart's Chart.yaml for the full explanation.
#
# A single addon failing to render does NOT abort the whole run -- everything
# else still gets rendered and handed to kubeconform/checkov -- but the
# script still exits non-zero (failing the CI job) if anything failed, so a
# real problem doesn't go unnoticed. See FAILED_ADDONS handling at the
# bottom.

set -u

OUT_DIR="${1:-rendered-upstream}"
GLOBAL_VALUES="${GLOBAL_VALUES:-ci/global-values.yaml}"
FAILED_LIST_FILE="$(mktemp)"

mkdir -p "$OUT_DIR"

# name|repoURL|chart|version|valuesPath|namespace
ADDONS='
aws-load-balancer-controller|https://aws.github.io/eks-charts|aws-load-balancer-controller|1.8.2|platform/aws-load-balancer-controller/values.yaml|kube-system
cert-manager|https://charts.jetstack.io|cert-manager|v1.20.3|platform/cert-manager/values.yaml|cert-manager
istio-base|https://istio-release.storage.googleapis.com/charts|base|1.30.2|platform/istio-base/values.yaml|istio-system
istio-cni|https://istio-release.storage.googleapis.com/charts|cni|1.30.2|platform/istio-cni/values.yaml|istio-system
istiod|https://istio-release.storage.googleapis.com/charts|istiod|1.30.2|platform/istiod/values.yaml|istio-system
ztunnel|https://istio-release.storage.googleapis.com/charts|ztunnel|1.30.2|platform/ztunnel/values.yaml|istio-system
kiali|https://kiali.org/helm-charts|kiali-server|1.89.0|platform/kiali/values.yaml|kiali
external-dns|https://kubernetes-sigs.github.io/external-dns/|external-dns|1.21.1|platform/external-dns/values.yaml|external-dns
external-secrets|https://charts.external-secrets.io|external-secrets|0.10.5|platform/external-secrets/values.yaml|external-secrets
kube-prometheus-stack|https://prometheus-community.github.io/helm-charts|kube-prometheus-stack|75.3.0|platform/kube-prometheus-stack/values.yaml|monitoring
loki|https://grafana.github.io/helm-charts|loki|6.45.2|platform/loki/values.yaml|monitoring
tempo|https://grafana.github.io/helm-charts|tempo|1.24.4|platform/tempo/values.yaml|monitoring
alloy|https://grafana.github.io/helm-charts|alloy|1.10.0|platform/alloy/values.yaml|monitoring
'

# Add each distinct classic Helm repo once.
echo "$ADDONS" | awk -F'|' 'NF>1 {print $2}' | sort -u | while read -r repo; do
  reponame=$(echo "$repo" | md5sum | cut -c1-12)
  helm repo add "r$reponame" "$repo" >/dev/null
done
helm repo update >/dev/null

echo "$ADDONS" | awk -F'|' 'NF>1' | while IFS='|' read -r name repo chart version valuesPath namespace; do
  reponame="r$(echo "$repo" | md5sum | cut -c1-12)"
  echo "== rendering upstream addon: $name ($chart @ $version from $repo) =="
  extra_set=""
  if [ "$name" = "aws-load-balancer-controller" ]; then
    # clusterName is intentionally blank in platform/aws-load-balancer-controller/values.yaml
    # (populated from the real EKS cluster name at deploy time, outside this
    # repo) -- the chart hard-requires a non-empty value to render at all, so
    # CI supplies a placeholder purely so `helm template` succeeds.
    extra_set="--set clusterName=ci-placeholder-cluster"
  fi
  # shellcheck disable=SC2086
  if ! helm template "$name" "$reponame/$chart" \
    --version "$version" \
    -f "$valuesPath" \
    -f "$GLOBAL_VALUES" \
    --namespace "$namespace" \
    $extra_set \
    --output-dir "$OUT_DIR/$name"; then
    echo "!! FAILED to render upstream addon: $name" >&2
    echo "$name" >> "$FAILED_LIST_FILE"
  fi
done

echo "rendered upstream addons into $OUT_DIR/"

if [ -s "$FAILED_LIST_FILE" ]; then
  echo "== upstream addon render FAILURES ==" >&2
  cat "$FAILED_LIST_FILE" >&2
  rm -f "$FAILED_LIST_FILE"
  exit 1
fi
rm -f "$FAILED_LIST_FILE"
echo "all upstream addons rendered successfully"
