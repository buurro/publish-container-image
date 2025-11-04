#!/bin/bash
set -euo pipefail

# Determine image name from inputs or Nix package
# Arguments:
#   $1: image-name input (optional)
#   $2: nix-flake-attr
#   $3: target registry
#   $4: github repository (fallback)
#
# Outputs: image name (without registry) to stdout
# Informational messages go to stderr

IMAGE_NAME_INPUT="${1:-}"
NIX_FLAKE_ATTR="$2"
TARGET_REGISTRY="$3"
GITHUB_REPO="$4"

# If image-name input is provided, use it
if [ -n "$IMAGE_NAME_INPUT" ]; then
  IMAGE_NAME="$IMAGE_NAME_INPUT"
  echo "Using provided image name: $IMAGE_NAME" >&2
else
  # Try to get imageName from Nix package
  if FULL_IMAGE_NAME=$(nix eval --raw "${NIX_FLAKE_ATTR}.imageName" 2>/dev/null); then
    if [ -n "$FULL_IMAGE_NAME" ]; then
      echo "Got imageName from Nix package: $FULL_IMAGE_NAME" >&2

      # Check if imageName contains a registry prefix
      # Registry pattern: domain.tld/ or domain.tld:port/ or localhost:port/
      if [[ "$FULL_IMAGE_NAME" =~ ^([a-zA-Z0-9.-]+(\.[a-zA-Z]{2,}|:[0-9]+)?)/(.+)$ ]]; then
        DETECTED_REGISTRY="${BASH_REMATCH[1]}"
        IMAGE_NAME="${BASH_REMATCH[3]}"

        echo "Detected registry in imageName: $DETECTED_REGISTRY" >&2
        echo "Extracted image name: $IMAGE_NAME" >&2

        if [ "$DETECTED_REGISTRY" != "$TARGET_REGISTRY" ]; then
          echo "⚠️  Warning: Nix imageName uses registry '$DETECTED_REGISTRY' but workflow will push to '$TARGET_REGISTRY'" >&2
          echo "    Final image will be: $TARGET_REGISTRY/$IMAGE_NAME" >&2
        fi
      else
        # No registry prefix detected, use as-is
        IMAGE_NAME="$FULL_IMAGE_NAME"
        echo "No registry prefix detected in imageName" >&2
        echo "Using image name: $IMAGE_NAME" >&2
      fi
    else
      IMAGE_NAME="$GITHUB_REPO"
      echo "Nix imageName is empty, using repository name: $IMAGE_NAME" >&2
    fi
  else
    IMAGE_NAME="$GITHUB_REPO"
    echo "Nix imageName not found, using repository name: $IMAGE_NAME" >&2
  fi
fi

echo "Final image will be: $TARGET_REGISTRY/$IMAGE_NAME" >&2

# Output only the image name to stdout
echo "$IMAGE_NAME"
