#!/usr/bin/env bash
# what it does: runs the vault-init python unit tests in the test container.
# use --audit to run the broader chart and provider audit, or --all to run both.
# run from the federator-suite-vault-init directory:
#   ./scripts/run-tests.sh
#   ./scripts/run-tests.sh --audit
#   ./scripts/run-tests.sh --all
# the audit requires python3, helm, jq, mike farah yq, and vault on the path.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/.." && pwd)"
python_bin="${PYTHON_BIN:-python3}"
if [[ "$python_bin" == "python3" && -x "$project_dir/.venv/bin/python" ]]; then
  python_bin="$project_dir/.venv/bin/python"
fi

run_unit_tests() {
  echo "== running vault-init unit tests =="
  "$script_dir/build-and-push-to-ecr.sh" --test
}

run_audit() {
  echo "== running chart and provider audit =="
  "$python_bin" "$project_dir/tests/audit.py"
}

case "${1:-unit}" in
  unit|--unit)
    run_unit_tests
    ;;
  audit|--audit)
    run_audit
    ;;
  all|--all)
    run_unit_tests
    run_audit
    ;;
  -h|--help)
    sed -n '2,9p' "$0"
    ;;
  *)
    echo "usage: $0 [--unit|--audit|--all]" >&2
    exit 2
    ;;
esac
