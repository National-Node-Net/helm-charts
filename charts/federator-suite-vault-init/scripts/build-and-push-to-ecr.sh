#!/usr/bin/env bash
# what it does: builds the vault-init image for one or more platforms and pushes
# it to the n3-vault-init ecr repository. with --test, it builds the test stage
# and runs the python unit tests locally in docker.vault-init
# run from the federator-suite-vault-init directory:
#   ./scripts/build-and-push-to-ecr.sh --test
#   ./scripts/build-and-push-to-ecr.sh
# the push path requires aws credentials, ecr access, and docker buildx.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TAG="1.0.1-$(date -u +%Y%m%d%H%M%S)"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
AWS_REGION="eu-west-2"

setup_multiarch_builder() {
  case ",${1}," in
    *,linux/arm64,*|*,linux/arm/v7,*|*,linux/arm/v6,*)
      echo "Installing binfmt handlers for multi-architecture builds..."
      docker run --privileged --rm tonistiigi/binfmt --install all
      ;;
  esac
  docker buildx inspect --bootstrap >/dev/null
}

if [[ "${1:-}" == "--test" ]]; then
  TEST_IMAGE="vault-init:test"
  TEST_PLATFORM="${TEST_PLATFORM:-linux/amd64}"
  setup_multiarch_builder "$TEST_PLATFORM"

  docker buildx build --platform "$TEST_PLATFORM" --target test --load --file "$APP_DIR/Dockerfile" --tag "$TEST_IMAGE" "$APP_DIR"
  docker run --rm --entrypoint python "$TEST_IMAGE" -m unittest discover -s /app -p 'test_*.py' -v
  exit 0
fi

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPOSITORY="n3-vault-init"
IMAGE="${REGISTRY}/${REPOSITORY}:${TAG}"

aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$REPOSITORY" >/dev/null
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"

setup_multiarch_builder "$PLATFORMS"

docker buildx build --platform "$PLATFORMS" --target runtime --file "$APP_DIR/Dockerfile" --tag "$IMAGE" --push "$APP_DIR"

printf 'Pushed %s (%s)\n' "$IMAGE" "$PLATFORMS"

aws ecr describe-images --region "$AWS_REGION" --repository-name "$REPOSITORY" --image-ids "imageTag=$TAG" --query 'imageDetails[0].{Digest:imageDigest,Tags:imageTags,PushedAt:imagePushedAt,SizeBytes:imageSizeInBytes}' --output table
