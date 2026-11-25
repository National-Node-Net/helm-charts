#!/bin/sh
# what it does: destroys the local vault and localstack volumes, regenerates
# all debug files, and starts a clean debug stack with the application attached
# to debugpy on port 5678.
# run from the federator-suite-vault-init directory:
#   ./scripts/reset-debug.sh
# this removes local debug state, including the generated vault root token.
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(CDPATH= cd -- "$script_dir/.." && pwd)"

cd "$project_dir"

docker compose -f docker-compose.debug.yml down -v
./scripts/generate-debug-files.sh
docker compose -f docker-compose.debug.yml up --build
