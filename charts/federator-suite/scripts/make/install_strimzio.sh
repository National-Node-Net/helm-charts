#!/usr/bin/env bash

# installs or verifies the strimzi operator used by bundled kafka resources.
# checks the required kafka custom resource definitions before installing.
# waits for the operator deployment to become available.

set -euo pipefail

STRIMZI_NAMESPACE="${STRIMZI_NAMESPACE:-strimzi-system}"
STRIMZI_RELEASE_NAME="${STRIMZI_RELEASE_NAME:-strimzi-kafka-operator}"
STRIMZI_CHART="${STRIMZI_CHART:-oci://quay.io/strimzi-helm/strimzi-kafka-operator}"
STRIMZI_VERSION="${STRIMZI_VERSION:-}"
TIMEOUT="${STRIMZI_TIMEOUT:-10m}"

required_crds=(
  kafkas.kafka.strimzi.io
  kafkanodepools.kafka.strimzi.io
  kafkausers.kafka.strimzi.io
)

for command in helm kubectl; do
  command -v "$command" >/dev/null 2>&1 || { echo "ERROR: $command is required to install Strimzi." >&2; exit 1; }
done

crds_installed=true
for crd in "${required_crds[@]}"; do
  if ! kubectl get crd "$crd" >/dev/null 2>&1; then crds_installed=false; break; fi
done

operator_installed=false
if kubectl get deployment strimzi-cluster-operator --namespace "$STRIMZI_NAMESPACE" >/dev/null 2>&1; then operator_installed=true; fi

if [ "$crds_installed" = false ] || [ "$operator_installed" = false ]; then
  echo "==> Installing Strimzi Kafka Operator in ${STRIMZI_NAMESPACE}..."
  chart_version_args=()
  if [ -n "$STRIMZI_VERSION" ]; then
    chart_version_args+=(--version "$STRIMZI_VERSION")
  fi

  helm upgrade --install "$STRIMZI_RELEASE_NAME" "$STRIMZI_CHART" --namespace "$STRIMZI_NAMESPACE" --create-namespace \
    --set watchAnyNamespace=true --wait --timeout "$TIMEOUT" "${chart_version_args[@]}"
else
  echo "==> Strimzi CRDs and operator already installed; verifying readiness..."
fi

for crd in "${required_crds[@]}"; do
  kubectl wait --for=condition=Established "crd/$crd" --timeout="$TIMEOUT"
done

# The official chart uses this stable Deployment name. A rollout wait also
# covers an existing operator installation whose CRDs were already present.
kubectl rollout status deployment/strimzi-cluster-operator --namespace "$STRIMZI_NAMESPACE" --timeout="$TIMEOUT"

echo "==> ✓ Strimzi Kafka Operator is ready"
