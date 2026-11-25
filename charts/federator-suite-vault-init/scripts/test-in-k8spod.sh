#!/usr/bin/env bash
# what it does: copies main.py into the selected kubernetes vault-init pod,
# checks for the expected startup phase, and compiles it. pass --run to execute
# the copied script against the vault service in that pod.
# run from the federator-suite-vault-init directory:
#   ./scripts/test-in-k8spod.sh
#   ./scripts/test-in-k8spod.sh --run
# override defaults with kube_context, kube_namespace, kube_pod, and
# kube_container environment variables.
set -euo pipefail

context="${KUBE_CONTEXT:-dev}"
namespace="${KUBE_NAMESPACE:-helm-federator-suite-bcc}"
pod="${KUBE_POD:-fs-bcc-vault-0}"
container="${KUBE_CONTAINER:-vault-setup}"
source_file="$(cd "$(dirname "$0")/.." && pwd)/vault-init/main.py"
target_file="/tmp/main.py"

echo "+ copying ${source_file} to ${pod}:${target_file}"
kubectl --context "$context" cp "$source_file" "${namespace}/${pod}:${target_file}" -c "$container"

echo "+ checking the Phase 1 log line"
kubectl --context "$context" exec "$pod" -n "$namespace" -c "$container" -- grep -n "Phase 1 - Waiting for Vault API" "$target_file"

echo "+ compiling ${target_file} inside the container"
kubectl --context "$context" exec "$pod" -n "$namespace" -c "$container" -- python -m py_compile "$target_file"

if [[ "${1:-}" == "--run" ]]; then
  echo "+ running the copied bootstrap script"
  kubectl --context "$context" exec -it "$pod" -n "$namespace" -c "$container" -- sh -c "echo START; python -u '$target_file'; echo EXIT:\$?"
else
  echo "+ syntax check complete; use --run to execute against Vault"
fi
