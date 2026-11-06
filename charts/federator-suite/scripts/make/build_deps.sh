#!/usr/bin/env bash

# builds the bundled chart dependencies used by the local deployment.
# uses the cached chart sources and does not update helm repositories.
# allows an already packaged dependency to remain usable offline.

set -eu

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

command -v helm >/dev/null 2>&1 || { echo "ERROR: helm is required to build dependencies." >&2; exit 1; }

echo "==> Building dependencies..."

(cd "$chart_dir/charts/valkey" && helm dependency build --skip-refresh 2>/dev/null) || true
(cd "$chart_dir/charts/vault" && helm dependency build --skip-refresh 2>/dev/null) || true
