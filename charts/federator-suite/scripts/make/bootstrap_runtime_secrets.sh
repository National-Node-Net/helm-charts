#!/usr/bin/env bash

# waits for the local vault setup to produce a usable token.
# writes the organisation runtime secrets json to the client-server vault path.
# leaves vault static secrets operator to create the kubernetes secrets.

set -euo pipefail

namespace="${1:?namespace is required}"
release_name="${2:?release name is required}"
secrets_file="${3:?runtime secrets file is required}"
credentials_secret="${release_name}-vault-credentials"
vault_pod="${release_name}-vault-0"

test -f "$secrets_file" || { echo "ERROR: $secrets_file not found" >&2; exit 1; }

# The complete JSON object is the Vault KV payload.
secret_data="$(jq -ce 'select(type == "object")' "$secrets_file")" || {
  echo "ERROR: $secrets_file must be a JSON object" >&2
  exit 1
}

# A previous Vault pod can leave this Secret behind with a token that is no
# longer valid for the newly started Vault. Wait until the token is accepted,
# not merely until the Secret exists.
credentials=""
vault_token=""
for attempt in $(seq 1 60); do
  encoded_credentials="$(kubectl get secret -n "$namespace" "$credentials_secret" -o jsonpath='{.data.vault-credentials}' 2>/dev/null || true)"
  if [ -n "$encoded_credentials" ]; then
    credentials="$(printf '%s' "$encoded_credentials" | base64 --decode 2>/dev/null || true)"
    vault_token="$(jq -er '.root_token' <<< "$credentials" 2>/dev/null || true)"
    if [ -n "$vault_token" ] && kubectl exec -n "$namespace" "$vault_pod" -c vault -- \
      env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$vault_token" vault token lookup >/dev/null 2>&1; then
      break
    fi
  fi
  sleep 2
done
[ -n "$vault_token" ] && kubectl exec -n "$namespace" "$vault_pod" -c vault -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$vault_token" vault token lookup >/dev/null 2>&1 || {
  echo "ERROR: Vault credentials secret $credentials_secret did not contain a valid token after 120s" >&2
  exit 1
}

# A successful token lookup also proves Vault is unsealed and serving requests.

echo "==> Writing federator-runtime-properties to Vault (secret/apps/client-server)..."
printf '%s' "$secret_data" | kubectl exec -i -n "$namespace" "$vault_pod" -c vault -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$vault_token" sh -ec '
    secret_file="$(mktemp)"
    trap "rm -f $secret_file" EXIT
    cat > "$secret_file"
    vault kv put -mount=secret apps/client-server @"$secret_file" >/dev/null
  '

echo "  ✓ Vault secret updated; VaultStaticSecret will refresh federator-runtime-properties."
