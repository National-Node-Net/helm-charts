#!/bin/sh
# what it does: reads the vault bootstrap json, including the generated root
# token, from localstack's aws secrets manager emulator.
# run after the debug compose stack has initialized vault:
#   ./scripts/get-aws-vault-token.sh
# the compose file exposes localstack on the local docker compose project.
set -eu

docker compose  -f docker-compose.debug.yml exec localstack awslocal secretsmanager get-secret-value --secret-id vault-init-credentials --query SecretString --output text
