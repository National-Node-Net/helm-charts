#!/usr/bin/env bash

# initializes a local vault server with one unseal key.
# enables the kv mounts used by the federator suite.
# creates the certificate manager token secret in the release namespace.

set -euo pipefail

environment="${1:?environment is required}"
namespace="${2:?namespace is required}"
release_name="${3:?release name is required}"
vault_pod="${release_name}-vault-0"

[ "$environment" = local ] || { echo "ERROR: init-vault only works with ENV=local" >&2; exit 1; }

echo "==> Initializing Vault (${vault_pod})..."
vault_init="$(kubectl exec -n "$namespace" "$vault_pod" -- vault operator init -key-shares=1 -key-threshold=1 -format=json)"
unseal_key="$(printf '%s' "$vault_init" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['unseal_keys_b64'][0])")"
root_token="$(printf '%s' "$vault_init" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['root_token'])")"

echo "  Unsealing..."
kubectl exec -n "$namespace" "$vault_pod" -- vault operator unseal "$unseal_key"
echo "  Enabling KV mounts..."
kubectl exec -n "$namespace" "$vault_pod" -- sh -c "VAULT_TOKEN=$root_token vault secrets enable -version=2 -path=secret kv 2>/dev/null || true"
kubectl exec -n "$namespace" "$vault_pod" -- sh -c "VAULT_TOKEN=$root_token vault secrets enable -version=2 -path=node-net kv 2>/dev/null || true"
echo "  Creating cert-manager vault-token secret..."
kubectl create secret generic "${release_name}-certificate-manager-vault-token" --from-literal=vault-token="$root_token" -n "$namespace" --dry-run=client -o yaml | kubectl apply -f -
echo "==> Vault initialized"
echo "    Unseal key : $unseal_key"
echo "    Root token : $root_token"
echo "    WARNING: save these credentials safely!"
