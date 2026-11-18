#!/bin/sh
# what it does: creates the local vault configuration, rendered policy/role
# files, vs code debug configuration, and a self-signed kubernetes ca used by
# the docker compose debug environment.
# run from the federator-suite-vault-init directory:
#   ./scripts/generate-debug-files.sh
# requires openssl and yq. the generated files are written to ./debug_files.
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
mkdir -p "$script_dir/../debug_files"
output_dir="$(CDPATH= cd -- "$script_dir/../debug_files" && pwd)"

cat > "$output_dir/vault.hcl" <<'EOF'
ui = true
disable_mlock = true

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable    = true
}

storage "file" {
  path = "/vault/file"
}

api_addr = "http://vault:8200"
EOF

policy_template="$script_dir/../../federator-suite/templates/vault/vault-init-policy.yaml"
debug_ca_key="$(mktemp)"
openssl req \
  -x509 \
  -newkey rsa:2048 \
  -nodes \
  -keyout "$debug_ca_key" \
  -out "$output_dir/kubernetes-ca.crt" \
  -days 10 \
  -subj "/CN=local-debug-kubernetes-ca" \
  >/dev/null 2>&1
rm -f "$debug_ca_key"

rendered_template="$(mktemp)"
trap 'rm -f "$rendered_template" "$debug_ca_key"' EXIT
sed \
  -n '/^data:/,$p' \
  "$policy_template" \
  | sed \
  -e 's/{{ include "certificateManager.serviceAccountName" \. | toJson }}/"certificate-manager"/g' \
  -e 's/{{ \.Release.Namespace | toJson }}/"default"/g' \
  -e '/{{.*}}/d' \
  > "$rendered_template"

for name in $(yq -r '.data | keys | .[]' "$rendered_template"); do
  yq -r ".data[\"$name\"]" "$rendered_template" > "$output_dir/$name"
done

mkdir -p "$output_dir/.vscode"
cat > "$output_dir/.vscode/launch.json" <<'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Attach to cloud-secret-py",
      "type": "debugpy",
      "request": "attach",
      "stopOnEntry": true,
      "justMyCode": false,
      "connect": { "host": "localhost", "port": 5678 },
      "pathMappings": [
        {
          "localRoot": "${workspaceFolder}/charts/federator-suite-vault-init/vault-init",
          "remoteRoot": "/app"
        }
      ]
    }
  ]
}
EOF


echo "Generated debug files in $output_dir - $(ls $output_dir)"
