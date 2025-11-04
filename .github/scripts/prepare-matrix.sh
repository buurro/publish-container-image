#!/bin/bash
set -euo pipefail

# Prepare build matrix from architectures input
# Arguments:
#   $1: architectures input (space/comma-separated string)
#   $2: ubuntu-version
#
# Outputs: JSON with matrix and architectures to stdout
# Informational messages go to stderr

ARCHS_INPUT="$1"
UBUNTU_VERSION="$2"

echo "Input architectures: $ARCHS_INPUT" >&2

# Convert space/comma-separated string to JSON array
# Replace commas with spaces, then split on whitespace
ARCHS_JSON=$(echo "$ARCHS_INPUT" | tr ',' ' ' | xargs -n1 | jq -R . | jq -s -c .)
echo "Parsed architectures: $ARCHS_JSON" >&2

# Validate architectures array is not empty
ARCH_COUNT=$(echo "$ARCHS_JSON" | jq 'length')
if [ "$ARCH_COUNT" -eq 0 ]; then
  echo "Error: architectures input must contain at least one architecture" >&2
  exit 1
fi

# Build matrix with runner mappings
MATRIX_JSON=$(echo "$ARCHS_JSON" | jq -c --arg ubuntu_version "$UBUNTU_VERSION" '[.[] | {
  arch: .,
  runner: (if . == "amd64" then "ubuntu-\($ubuntu_version)"
           elif . == "arm64" then "ubuntu-\($ubuntu_version)-arm"
           else error("Unsupported architecture: " + .) end)
}]')

echo "Generated matrix: $MATRIX_JSON" >&2

# Output results to stdout
jq -n -c \
  --argjson matrix "$MATRIX_JSON" \
  --argjson archs "$ARCHS_JSON" \
  '{matrix: {include: $matrix}, architectures: $archs}'
