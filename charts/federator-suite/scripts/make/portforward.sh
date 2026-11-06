#!/usr/bin/env bash

# starts, stops, or lists local port forwards for release services.
# forwards the dashboard and user interface services to localhost ports.
# limits stop and status actions to the requested namespace.

set -euo pipefail

namespace="${1:?namespace is required}"
release_name="${2:?release name is required}"

case "${3:?start, stop, or status is required}" in
  start)
    kubectl port-forward -n "$namespace" "svc/${release_name}-kafka-ui" 8088:8080 >/dev/null 2>&1 &
    kubectl port-forward -n "$namespace" "svc/${release_name}-valkey-ui" 5540:5540 >/dev/null 2>&1 &
    kubectl port-forward -n "$namespace" "svc/${release_name}-federator-client" 8085:8085 >/dev/null 2>&1 &
    kubectl port-forward -n "$namespace" "svc/${release_name}-vault-ui" 8200:8200 >/dev/null 2>&1 &
    kubectl port-forward -n "$namespace" "svc/${release_name}-opa" 8181:8181 >/dev/null 2>&1 &
    echo "✓ JobRunr:    http://localhost:8085"
    echo "✓ Kafka UI:   http://localhost:8088"
    echo "✓ Valkey UI:  http://localhost:5540"
    echo "✓ Vault UI:   http://localhost:8200"
    echo "✓ OPA:        http://localhost:8181"
    ;;
  stop)
    pids="$(ps aux | grep '[k]ubectl port-forward' | grep -- "-n $namespace" | awk '{print $2}' || true)"
    [ -n "$pids" ] && echo "$pids" | xargs kill || echo "No port forwards running"
    ;;
  status)
    ps aux | grep '[k]ubectl port-forward' | grep -- "-n $namespace" || echo "No port forwards running"
    ;;
  *)
    echo "ERROR: use start, stop, or status." >&2
    exit 1
    ;;
esac
