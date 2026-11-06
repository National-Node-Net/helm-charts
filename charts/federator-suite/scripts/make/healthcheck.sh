#!/usr/bin/env bash

# reports pod and service state for a deployed federator suite release.
# checks the main application, vault, certificate manager, and opa containers.
# scans recent pod logs for likely runtime errors.

set -euo pipefail

namespace="${1:?namespace is required}"
release_name="${2:?release name is required}"

echo "==> Health check: ${release_name} in ${namespace}"
echo ""
echo "All Pods:"
kubectl get pods -n "$namespace"

failed=0
not_running="$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -v 'Running\|Completed' || true)"
if [ -n "$not_running" ]; then
  echo "⚠ Pods not in Running state:"
  echo "$not_running"
  failed=1
fi

not_ready="$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | awk '{split($2,a,"/"); if(a[1]!=a[2] && $3=="Running") print $0}' || true)"
if [ -n "$not_ready" ]; then
  echo "⚠ Pods running but not ready:"
  echo "$not_ready"
  failed=1
fi

[ "$failed" -eq 0 ] && echo "✓ All pods Running and Ready"

echo ""
echo "Services:"
kubectl get svc -n "$namespace"

echo ""
echo "Application health:"
server_pod="$(kubectl get pod -l app=federator-server -n "$namespace" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -z "$server_pod" ]; then echo "  ⚠ server pod not found"; else
  kubectl exec -n "$namespace" "$server_pod" -c federator-server -- sh -c "ps aux | grep -q '[j]ava.*FederatorServer' && echo '  ✓ Server process running' || echo '  ⚠ Server process not found'" 2>/dev/null || echo "  ⚠ Cannot check server process"
fi

client_pod="$(kubectl get pod -l app=federator-client -n "$namespace" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -z "$client_pod" ]; then echo "  ⚠ client pod not found"; else
  kubectl exec -n "$namespace" "$client_pod" -c federator-client -- sh -c "if command -v wget >/dev/null; then wget -qO- --timeout=2 http://localhost:8085/ 2>/dev/null | grep -q 'JobRunr' && echo '  ✓ JobRunr dashboard responding' || echo '  ⚠ JobRunr not responding'; else echo '  ⚠ wget not available'; fi" 2>/dev/null || echo "  ⚠ Cannot check JobRunr"
fi

echo ""
echo "Vault health:"
vault_pod="$(kubectl get pod -l app.kubernetes.io/name=vault,component=server -n "$namespace" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -z "$vault_pod" ]; then echo "  ⚠ vault pod not found"; else
  kubectl exec -n "$namespace" "$vault_pod" -- vault status 2>/dev/null && echo "  ✓ Vault responding" || echo "  ⚠ Vault not responding (may need init)"
fi

echo ""
echo "Certificate Manager health:"
cm_pod="$(kubectl get pod -l app=certificate-manager -n "$namespace" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -z "$cm_pod" ]; then echo "  ⚠ certificate-manager pod not found"; else
  kubectl exec -n "$namespace" "$cm_pod" -- sh -c "pgrep -f 'java.*certificate-manager' > /dev/null && echo '  ✓ Certificate manager process running' || echo '  ⚠ Certificate manager process not found'" 2>/dev/null || echo "  ⚠ Cannot check certificate manager"
fi

echo ""
echo "OPA health:"
opa_pod="$(kubectl get pod -l app=opa -n "$namespace" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -z "$opa_pod" ]; then echo "  ⚠ opa pod not found"; else
  ready="$(kubectl get pod "$opa_pod" -n "$namespace" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)"
  [ "$ready" = true ] && echo "  ✓ OPA responding (readiness probe: /health/ready)" || echo "  ⚠ OPA not ready"
fi

echo ""
echo "Error check (all pods, last 100 lines):"
error_found=0
for pod in $(kubectl get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  errors="$(kubectl logs "$pod" -n "$namespace" --tail=100 --all-containers 2>/dev/null | grep -Ei 'error|exception|fatal|crash' | grep -Eiv 'loglevel.*error|error.*level|expected.*error' || true)"
  if [ -n "$errors" ]; then
    echo "⚠ Errors in $pod:"
    echo "$errors" | head -5
    error_found=1
  fi
done

[ "$error_found" -eq 0 ] && echo "  ✓ No errors found in any pods"
