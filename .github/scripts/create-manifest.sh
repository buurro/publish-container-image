#!/bin/bash
set -euo pipefail

# Create and push multi-architecture manifest
# Arguments:
#   $1: registry
#   $2: image name
#   $3: image tag
#   $4: architectures (JSON array)
#   $5: tag-latest (true/false)
#
# All output goes to stderr for logging
# This script performs actions, doesn't return data

REGISTRY="$1"
IMAGE_NAME="$2"
IMAGE_TAG="$3"
ARCHITECTURES="$4"
TAG_LATEST="$5"

echo "Creating manifests for: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG" >&2
echo "Architectures: $ARCHITECTURES" >&2

# Build list of architecture-specific images
ARCH_IMAGES=()
for arch in $(echo "$ARCHITECTURES" | jq -r '.[]'); do
  ARCH_IMAGES+=("--amend" "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG-$arch")
done

# Create version-tagged manifest
echo "Creating manifest for tag: $IMAGE_TAG" >&2
docker manifest create "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG" "${ARCH_IMAGES[@]}"

# Annotate each architecture
for arch in $(echo "$ARCHITECTURES" | jq -r '.[]'); do
  echo "Annotating $arch architecture" >&2
  docker manifest annotate "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG" \
    "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG-$arch" \
    --arch "$arch" --os linux
done

docker manifest push "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo "✓ Pushed manifest: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG" >&2

# Create and push latest manifest if enabled
if [[ "$TAG_LATEST" == "true" ]]; then
  echo "Creating manifest for tag: latest" >&2
  docker manifest create "$REGISTRY/$IMAGE_NAME:latest" "${ARCH_IMAGES[@]}"

  # Annotate each architecture for latest tag
  for arch in $(echo "$ARCHITECTURES" | jq -r '.[]'); do
    echo "Annotating $arch architecture for latest" >&2
    docker manifest annotate "$REGISTRY/$IMAGE_NAME:latest" \
      "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG-$arch" \
      --arch "$arch" --os linux
  done

  docker manifest push "$REGISTRY/$IMAGE_NAME:latest"
  echo "✓ Pushed manifest: $REGISTRY/$IMAGE_NAME:latest" >&2
fi
