#!/usr/bin/env bash
# what it does: runs the vault-init python unit tests.
# use --docker to run the same tests in the multi-stage docker test image.
# run from the federator-suite-vault-init directory:
#   ./scripts/run-tests.sh
#   ./scripts/run-tests.sh --docker
# dependencies are installed into .venv with uv when a local uv environment exists.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/.." && pwd)"
python_bin="${PYTHON_BIN:-python3}"
if [[ "$python_bin" == "python3" && -x "$project_dir/.venv/bin/python" ]]; then
  python_bin="$project_dir/.venv/bin/python"
fi

run_unit_tests() {
  echo "== running vault-init unit tests =="
  if [[ -x "$project_dir/.venv/bin/python" ]]; then
    "$python_bin" -m unittest discover -s "$project_dir/vault-init" -p 'test_*.py' -v
  else
    "$script_dir/build-and-push-to-ecr.sh" --test
  fi
}

case "${1:-}" in
  "")
    run_unit_tests
    ;;
  docker|--docker)
    echo "== running vault-init unit tests in docker =="
    "$script_dir/build-and-push-to-ecr.sh" --test
    ;;
  -h|--help)
    sed -n '2,9p' "$0"
    ;;
  *)
    echo "usage: $0 [--docker]" >&2
    exit 2
    ;;
esac
