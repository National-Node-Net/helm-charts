#!/bin/sh
# what it does: runs automatically inside localstack when the service becomes
# ready and creates the placeholder vault bootstrap secret used by the debug
# environment. the application replaces it with the real generated token after
# vault initialization.
# test it by starting the debug stack:
#   docker compose -f docker-compose.debug.yml up --build
# do not run this script directly on the host; localstack mounts it as a ready
# hook and provides the awslocal command.
set -eu

awslocal secretsmanager create-secret \
  --name vault-init-credentials \
  --secret-string '{"root_token":"debug-root"}' \
  >/dev/null 2>&1 || true

echo "LocalStack Secrets Manager is ready"
