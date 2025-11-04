#!/bin/bash
set -euo pipefail

# Validate workflow inputs for security
# Arguments:
#   $1: nix-flake-attr
#   $2: registry
#   $3: image-name
#   $4: architectures
#   $5: ubuntu-version
#
# Exits with error if validation fails

NIX_FLAKE_ATTR="${1:-}"
REGISTRY="${2:-}"
IMAGE_NAME="${3:-}"
ARCHITECTURES="${4:-}"
UBUNTU_VERSION="${5:-}"

echo "Validating inputs..." >&2

# Validate nix-flake-attr
if [ -n "$NIX_FLAKE_ATTR" ]; then
  # Only allow alphanumeric, dot, hash, hyphen, underscore, slash
  if [[ ! "$NIX_FLAKE_ATTR" =~ ^[a-zA-Z0-9.#_/-]+$ ]]; then
    echo "❌ Error: nix-flake-attr contains invalid characters" >&2
    echo "   Allowed: alphanumeric, dot, hash, hyphen, underscore, slash" >&2
    echo "   Got: $NIX_FLAKE_ATTR" >&2
    exit 1
  fi

  # Must start with .# or /
  if [[ ! "$NIX_FLAKE_ATTR" =~ ^\.#.+ ]] && [[ ! "$NIX_FLAKE_ATTR" =~ ^/.+ ]]; then
    echo "❌ Error: nix-flake-attr must start with '.#' or '/'" >&2
    echo "   Got: $NIX_FLAKE_ATTR" >&2
    exit 1
  fi

  # No command injection patterns
  if [[ "$NIX_FLAKE_ATTR" =~ [\;\|\&\$\`] ]]; then
    echo "❌ Error: nix-flake-attr contains shell metacharacters" >&2
    exit 1
  fi

  echo "✓ nix-flake-attr: $NIX_FLAKE_ATTR" >&2
fi

# Validate registry
if [ -n "$REGISTRY" ]; then
  # Registry must be a valid domain/hostname
  if [[ ! "$REGISTRY" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*(:[0-9]+)?$ ]]; then
    echo "❌ Error: registry is not a valid hostname" >&2
    echo "   Got: $REGISTRY" >&2
    exit 1
  fi

  # Allowlist of known safe registries (optional - can be disabled)
  ALLOWED_REGISTRIES=(
    "ghcr.io"
    "docker.io"
    "quay.io"
    "gcr.io"
    "registry.hub.docker.com"
  )

  # Check if registry is in allowlist (warning only)
  REGISTRY_ALLOWED=false
  for allowed in "${ALLOWED_REGISTRIES[@]}"; do
    if [[ "$REGISTRY" == "$allowed"* ]]; then
      REGISTRY_ALLOWED=true
      break
    fi
  done

  if [ "$REGISTRY_ALLOWED" = false ]; then
    echo "⚠️  Warning: Registry '$REGISTRY' is not in the known safe list" >&2
    echo "   Allowed: ${ALLOWED_REGISTRIES[*]}" >&2
    echo "   Proceeding anyway..." >&2
  fi

  echo "✓ registry: $REGISTRY" >&2
fi

# Validate image-name
if [ -n "$IMAGE_NAME" ]; then
  # Image name: alphanumeric, dot, hyphen, underscore, slash (for org/repo)
  if [[ ! "$IMAGE_NAME" =~ ^[a-z0-9._/-]+$ ]]; then
    echo "❌ Error: image-name contains invalid characters" >&2
    echo "   Allowed: lowercase alphanumeric, dot, hyphen, underscore, slash" >&2
    echo "   Got: $IMAGE_NAME" >&2
    exit 1
  fi

  # No path traversal
  if [[ "$IMAGE_NAME" =~ \.\. ]]; then
    echo "❌ Error: image-name contains path traversal (..)" >&2
    exit 1
  fi

  # No leading/trailing slashes
  if [[ "$IMAGE_NAME" =~ ^/ ]] || [[ "$IMAGE_NAME" =~ /$ ]]; then
    echo "❌ Error: image-name cannot start or end with '/'" >&2
    exit 1
  fi

  echo "✓ image-name: $IMAGE_NAME" >&2
fi

# Validate architectures
if [ -n "$ARCHITECTURES" ]; then
  # Only allow known architectures
  for arch in $(echo "$ARCHITECTURES" | tr ',' ' '); do
    arch=$(echo "$arch" | xargs)  # trim whitespace
    if [[ ! "$arch" =~ ^(amd64|arm64|arm|386|ppc64le|s390x)$ ]]; then
      echo "❌ Error: Unknown architecture: $arch" >&2
      echo "   Allowed: amd64, arm64, arm, 386, ppc64le, s390x" >&2
      exit 1
    fi
  done
  echo "✓ architectures: $ARCHITECTURES" >&2
fi

# Validate ubuntu-version
if [ -n "$UBUNTU_VERSION" ]; then
  # Only allow specific Ubuntu versions
  if [[ ! "$UBUNTU_VERSION" =~ ^(20\.04|22\.04|24\.04)$ ]]; then
    echo "❌ Error: Unknown ubuntu-version: $UBUNTU_VERSION" >&2
    echo "   Allowed: 20.04, 22.04, 24.04" >&2
    exit 1
  fi
  echo "✓ ubuntu-version: $UBUNTU_VERSION" >&2
fi

echo "✅ All inputs validated successfully" >&2
