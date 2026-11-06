#!/usr/bin/env bash

# installs or verifies vault secrets operator for vault custom resources.
# checks the required custom resource definitions before installing.
# waits for the operator deployment to become available.

set -euo pipefail

VSO_NAMESPACE="${VSO_NAMESPACE:-vault-secrets-operator-system}"
VSO_RELEASE_NAME="${VSO_RELEASE_NAME:-vault-secrets-operator}"
VSO_CHART="${VSO_CHART:-hashicorp/vault-secrets-operator}"
VSO_VERSION="${VSO_VERSION:-}"
TIMEOUT="${VSO_TIMEOUT:-10m}"

required_crds=(
  vaultauths.secrets.hashicorp.com
  vaultconnections.secrets.hashicorp.com
  vaultstaticsecrets.secrets.hashicorp.com
)

for command in helm kubectl; do
  command -v "$command" >/dev/null 2>&1 || { echo "ERROR: $command is required to install Vault Secrets Operator." >&2; exit 1; }
done

crds_installed=true
for crd in "${required_crds[@]}"; do
  if ! kubectl get crd "$crd" >/dev/null 2>&1; then crds_installed=false; break; fi
done

operator_installed=false
if kubectl get deployment --namespace "$VSO_NAMESPACE" -l "app.kubernetes.io/instance=$VSO_RELEASE_NAME" -o name 2>/dev/null | grep -q .; then operator_installed=true; fi

if [ "$crds_installed" = false ] || [ "$operator_installed" = false ]; then
  echo "==> Installing Vault Secrets Operator in ${VSO_NAMESPACE}..."
  if ! helm repo list 2>/dev/null | grep -q '^hashicorp[[:space:]]'; then
    helm repo add hashicorp https://helm.releases.hashicorp.com
  fi

  chart_version_args=()
  if [ -n "$VSO_VERSION" ]; then
    chart_version_args+=(--version "$VSO_VERSION")
  fi

  helm upgrade --install "$VSO_RELEASE_NAME" "$VSO_CHART" --namespace "$VSO_NAMESPACE" --create-namespace \
    --wait --timeout "$TIMEOUT" "${chart_version_args[@]}"
else
  echo "==> Vault Secrets Operator CRDs and controller already installed; verifying readiness..."
fi

for crd in "${required_crds[@]}"; do
  kubectl wait --for=condition=Established "crd/$crd" --timeout="$TIMEOUT"
done

deployments="$(kubectl get deployment --namespace "$VSO_NAMESPACE" -l "app.kubernetes.io/instance=$VSO_RELEASE_NAME" -o name)"
[ -n "$deployments" ] || { echo "ERROR: Vault Secrets Operator installation has no controller Deployment." >&2; exit 1; }

while IFS= read -r deployment; do
  [ -n "$deployment" ] && kubectl rollout status "$deployment" --namespace "$VSO_NAMESPACE" --timeout="$TIMEOUT"
done <<< "$deployments"

echo "==> ✓ Vault Secrets Operator is ready"
