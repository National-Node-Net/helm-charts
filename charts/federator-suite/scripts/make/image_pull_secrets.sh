#!/usr/bin/env bash

# creates or refreshes the namespace image pull secret.
# reads registry credentials from the json passed by the make target.
# supports the configured registry type without writing credentials to disk.

set -euo pipefail

# usage:
#   make image_pull_secrets TYPE=aws CREDS='{"AWS_PROFILE":"dev","AWS_REGION":"eu-west-2"}'
#   make image_pull_secrets TYPE=gcp CREDS='{"GCP_SERVICE_ACCOUNT":"{...service-account JSON...}"}'
#   make image_pull_secrets TYPE=ghcr CREDS='{"USERNAME":"...","TOKEN":"..."}'

namespace="${1:?namespace is required}"
type="${2:?TYPE is required}"
creds="${3:?CREDS is required}"
secret_name=image-pull-creds

case "$type" in
  aws)
    export AWS_PROFILE="$(jq -er '.AWS_PROFILE' <<< "$creds")"
    aws_region="$(jq -er '.AWS_REGION' <<< "$creds")"
    account_id="$(aws sts get-caller-identity --query Account --output text)"
    registry="${account_id}.dkr.ecr.${aws_region}.amazonaws.com"
    username=AWS
    password="$(aws ecr get-login-password --region "$aws_region")"
    ;;
  gcp)
    # Todo
    ;;
  ghcr)
    # Todo
    ;;
  *)
    echo "ERROR: TYPE must be aws, gcp, or ghcr." >&2
    exit 1
    ;;
esac

echo "==> Creating ${type} image-pull Secret ${secret_name} in ${namespace} for ${registry}..."
kubectl create secret docker-registry "$secret_name" --namespace "$namespace" \
  --docker-server="$registry" --docker-username="$username" --docker-password="$password" \
  --dry-run=client -o yaml | kubectl apply -f -
