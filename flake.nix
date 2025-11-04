{
  description = "Reusable GitHub Action for publishing multi-architecture container images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        version = "0.2.0";
      in
      {
        packages = {
          # Minimal container image for testing the action
          containerImage = pkgs.dockerTools.streamLayeredImage {
            name = "ghcr.io/buurro/publish-container-image";
            tag = version;
            contents = [
              pkgs.busybox
            ];
            config = {
              Cmd = [ "sh" "-c" "echo 'Hello from publish-container-image test image!'; sleep infinity" ];
              Labels = {
                "org.opencontainers.image.title" = "publish-container-image-test";
                "org.opencontainers.image.description" = "Test image for publish-container-image GitHub Action";
                "org.opencontainers.image.version" = version;
                "org.opencontainers.image.source" = "https://github.com/buurro/publish-container-image";
              };
            };
          };

          default = self.packages.${system}.containerImage;
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nix
            docker
            jq
            python3
            python3Packages.pytest
          ];

          shellHook = ''
            echo "publish-container-image development environment"
            echo ""
            echo "Build and run:"
            echo "  nix build .#containerImage           - Build the test container image"
            echo "  ./result | docker load               - Load the built image into Docker"
            echo ""
            echo "Test workflow locally:"
            echo "  nix run .#workflow-prepare           - Test complete preparation phase"
            echo "  nix run .#build-and-load-image       - Test build and load"
            echo "  nix run .#tag-and-push-image         - Test tag and push"
            echo ""
            echo "Test individual helpers:"
            echo "  nix run .#validate-inputs            - Test input validation"
            echo "  nix run .#determine-image-name       - Test image name extraction"
            echo "  nix run .#prepare-matrix             - Test matrix preparation"
            echo ""
            echo "Run test suites:"
            echo "  nix run .#test-scripts               - Test workflow apps (pytest)"
            echo "  nix run .#test-validation            - Test input validation (pytest)"
          '';
        };

        # Test the bash scripts with pytest
        apps.test-scripts = {
          type = "app";
          program = toString (pkgs.writeShellScript "test-scripts" ''
            set -e
            echo "=== Running pytest script tests ==="
            echo ""

            cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"

            # Use Python with pytest available
            ${(pkgs.python3.withPackages (ps: [ ps.pytest ]))}/bin/python -m pytest tests/test_scripts.py -v --tb=short
          '');
        };

        # Test input validation with pytest
        apps.test-validation = {
          type = "app";
          program = toString (pkgs.writeShellScript "test-validation" ''
            set -e
            echo "=== Running pytest validation tests ==="
            echo ""

            cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"

            # Use Python with pytest available
            ${(pkgs.python3.withPackages (ps: [ ps.pytest ]))}/bin/python -m pytest tests/test_validation.py -v --tb=short
          '');
        };

        # Workflow helper apps (used by GitHub Actions)
        # These replace the bash scripts in .github/scripts/

        apps.validate-inputs = {
          type = "app";
          program = toString (pkgs.writeShellScript "validate-inputs" ''
            # Validate workflow inputs for security
            # Usage: nix run .#validate-inputs NIX_ATTR REGISTRY IMAGE_NAME ARCHITECTURES UBUNTU_VERSION
            ${pkgs.bash}/bin/bash ${./.github/scripts/validate-inputs.sh} "$@"
          '');
        };

        apps.determine-image-name = {
          type = "app";
          program = toString (pkgs.writeShellScript "determine-image-name" ''
            # Determine the image name from Nix or custom input
            # Usage: nix run .#determine-image-name IMAGE_NAME NIX_ATTR REGISTRY GITHUB_REPO
            ${pkgs.bash}/bin/bash ${./.github/scripts/determine-image-name.sh} "$@"
          '');
        };

        apps.prepare-matrix = {
          type = "app";
          program = toString (pkgs.writeShellScript "prepare-matrix" ''
            # Prepare the build matrix for multi-architecture builds
            # Usage: nix run .#prepare-matrix ARCHITECTURES UBUNTU_VERSION
            ${pkgs.bash}/bin/bash ${./.github/scripts/prepare-matrix.sh} "$@"
          '');
        };

        apps.create-manifest = {
          type = "app";
          program = toString (pkgs.writeShellScript "create-manifest" ''
            # Create multi-architecture manifest
            # Usage: nix run .#create-manifest REGISTRY IMAGE_NAME TAG ARCHITECTURES TAG_LATEST
            ${pkgs.bash}/bin/bash ${./.github/scripts/create-manifest.sh} "$@"
          '');
        };

        # High-level workflow apps (orchestrate multiple steps)

        apps.prepare-and-validate = {
          type = "app";
          program = toString (pkgs.writeShellScript "prepare-and-validate" ''
            set -euo pipefail

            # Combined validation and preparation step
            # Usage: nix run .#prepare-and-validate NIX_ATTR REGISTRY IMAGE_NAME ARCHITECTURES UBUNTU_VERSION GITHUB_REPO
            # Outputs JSON with all prepared values

            NIX_ATTR="''${1:-.#containerImage}"
            REGISTRY="''${2:-ghcr.io}"
            IMAGE_NAME="''${3:-}"
            ARCHITECTURES="''${4:-amd64 arm64}"
            UBUNTU_VERSION="''${5:-24.04}"
            GITHUB_REPO="''${6:-}"

            echo "=== Validating inputs ===" >&2
            ${pkgs.bash}/bin/bash ${./.github/scripts/validate-inputs.sh} \
              "$NIX_ATTR" "$REGISTRY" "$IMAGE_NAME" "$ARCHITECTURES" "$UBUNTU_VERSION"

            echo "=== Determining image name ===" >&2
            DETERMINED_IMAGE_NAME=$(${pkgs.bash}/bin/bash ${./.github/scripts/determine-image-name.sh} \
              "$IMAGE_NAME" "$NIX_ATTR" "$REGISTRY" "$GITHUB_REPO")

            echo "=== Preparing build matrix ===" >&2
            MATRIX_RESULT=$(${pkgs.bash}/bin/bash ${./.github/scripts/prepare-matrix.sh} \
              "$ARCHITECTURES" "$UBUNTU_VERSION")

            # Output combined JSON
            ${pkgs.jq}/bin/jq -n -c \
              --arg image_name "$DETERMINED_IMAGE_NAME" \
              --argjson matrix_data "$MATRIX_RESULT" \
              '{
                image_name: $image_name,
                matrix: $matrix_data.matrix,
                architectures: $matrix_data.architectures
              }'
          '');
        };

        apps.build-and-load-image = {
          type = "app";
          program = toString (pkgs.writeShellScript "build-and-load-image" ''
            set -euo pipefail

            # Build Nix container image and load into Docker
            # Usage: nix run .#build-and-load-image NIX_ATTR
            # Outputs JSON with image metadata

            NIX_ATTR="''${1:-.#containerImage}"

            echo "=== Building container image ===" >&2
            ${pkgs.nix}/bin/nix build -L "$NIX_ATTR" 2>&2

            if [ ! -f ./result ]; then
              echo "Error: Nix build result not found" >&2
              exit 1
            fi

            echo "=== Loading image into Docker ===" >&2
            ./result | ${pkgs.docker}/bin/docker load >&2

            echo "=== Extracting image metadata ===" >&2
            IMAGE_TAG=$(${pkgs.nix}/bin/nix eval --raw "$NIX_ATTR.imageTag" 2>&2)
            NIX_IMAGE_NAME=$(${pkgs.nix}/bin/nix eval --raw "$NIX_ATTR.imageName" 2>&2)

            if [ -z "$IMAGE_TAG" ]; then
              echo "Error: Failed to extract image tag" >&2
              exit 1
            fi

            if [ -z "$NIX_IMAGE_NAME" ]; then
              echo "Error: Failed to extract image name from Nix" >&2
              exit 1
            fi

            echo "Image loaded successfully: $NIX_IMAGE_NAME:$IMAGE_TAG" >&2

            # Output JSON (only thing going to stdout)
            ${pkgs.jq}/bin/jq -n -c \
              --arg tag "$IMAGE_TAG" \
              --arg nix_name "$NIX_IMAGE_NAME" \
              '{
                tag: $tag,
                nix_image_name: $nix_name
              }'
          '');
        };

        apps.tag-and-push-image = {
          type = "app";
          program = toString (pkgs.writeShellScript "tag-and-push-image" ''
            set -euo pipefail

            # Retag (if needed) and push architecture-specific image
            # Usage: nix run .#tag-and-push-image REGISTRY TARGET_IMAGE_NAME NIX_IMAGE_NAME TAG ARCH
            # Note: Requires docker login to be done beforehand

            REGISTRY="$1"
            TARGET_IMAGE_NAME="$2"
            NIX_IMAGE_NAME="$3"
            TAG="$4"
            ARCH="$5"

            echo "=== Preparing to push image ===" >&2
            echo "Registry: $REGISTRY" >&2
            echo "Target: $REGISTRY/$TARGET_IMAGE_NAME:$TAG" >&2
            echo "Nix name: $NIX_IMAGE_NAME:$TAG" >&2
            echo "Architecture: $ARCH" >&2

            # Retag if custom image name differs from Nix name
            if [ "$NIX_IMAGE_NAME" != "$REGISTRY/$TARGET_IMAGE_NAME" ]; then
              echo "Re-tagging from Nix name to target name..." >&2
              ${pkgs.docker}/bin/docker image tag "$NIX_IMAGE_NAME:$TAG" "$REGISTRY/$TARGET_IMAGE_NAME:$TAG"
            else
              echo "Image name matches, no retagging needed" >&2
            fi

            # Verify the image exists
            if ! ${pkgs.docker}/bin/docker image inspect "$REGISTRY/$TARGET_IMAGE_NAME:$TAG" >/dev/null 2>&1; then
              echo "Error: Expected image not found: $REGISTRY/$TARGET_IMAGE_NAME:$TAG" >&2
              echo "Available images:" >&2
              ${pkgs.docker}/bin/docker images >&2
              exit 1
            fi

            # Tag with architecture suffix and push
            ARCH_TAG="$TAG-$ARCH"
            echo "Tagging as $REGISTRY/$TARGET_IMAGE_NAME:$ARCH_TAG" >&2
            ${pkgs.docker}/bin/docker image tag "$REGISTRY/$TARGET_IMAGE_NAME:$TAG" "$REGISTRY/$TARGET_IMAGE_NAME:$ARCH_TAG"

            echo "Pushing $REGISTRY/$TARGET_IMAGE_NAME:$ARCH_TAG" >&2
            ${pkgs.docker}/bin/docker push "$REGISTRY/$TARGET_IMAGE_NAME:$ARCH_TAG"

            echo "Successfully pushed $REGISTRY/$TARGET_IMAGE_NAME:$ARCH_TAG" >&2
          '');
        };

        apps.workflow-prepare = {
          type = "app";
          program = toString (pkgs.writeShellScript "workflow-prepare" ''
            # Complete preparation phase of the workflow
            # This can be tested locally to validate all workflow inputs
            # Usage: nix run .#workflow-prepare
            # Options passed as environment variables:
            #   NIX_FLAKE_ATTR, REGISTRY, IMAGE_NAME, ARCHITECTURES, UBUNTU_VERSION, GITHUB_REPOSITORY

            set -euo pipefail

            NIX_ATTR="''${NIX_FLAKE_ATTR:-.#containerImage}"
            REGISTRY="''${REGISTRY:-ghcr.io}"
            IMAGE_NAME="''${IMAGE_NAME:-}"
            ARCHITECTURES="''${ARCHITECTURES:-amd64 arm64}"
            UBUNTU_VERSION="''${UBUNTU_VERSION:-24.04}"
            GITHUB_REPO="''${GITHUB_REPOSITORY:-}"

            echo "=== Workflow Preparation Phase ===" >&2
            echo "" >&2
            echo "Configuration:" >&2
            echo "  Nix flake attribute: $NIX_ATTR" >&2
            echo "  Registry: $REGISTRY" >&2
            echo "  Custom image name: ''${IMAGE_NAME:-<auto-detect from Nix>}" >&2
            echo "  Architectures: $ARCHITECTURES" >&2
            echo "  Ubuntu version: $UBUNTU_VERSION" >&2
            echo "  GitHub repository: $GITHUB_REPO" >&2
            echo "" >&2

            # Validate inputs
            echo "=== Validating inputs ===" >&2
            ${pkgs.bash}/bin/bash ${./.github/scripts/validate-inputs.sh} \
              "$NIX_ATTR" "$REGISTRY" "$IMAGE_NAME" "$ARCHITECTURES" "$UBUNTU_VERSION"

            # Determine image name
            echo "=== Determining image name ===" >&2
            DETERMINED_IMAGE_NAME=$(${pkgs.bash}/bin/bash ${./.github/scripts/determine-image-name.sh} \
              "$IMAGE_NAME" "$NIX_ATTR" "$REGISTRY" "$GITHUB_REPO")

            # Prepare build matrix
            echo "=== Preparing build matrix ===" >&2
            MATRIX_RESULT=$(${pkgs.bash}/bin/bash ${./.github/scripts/prepare-matrix.sh} \
              "$ARCHITECTURES" "$UBUNTU_VERSION")

            # Output combined JSON
            RESULT=$(${pkgs.jq}/bin/jq -n -c \
              --arg image_name "$DETERMINED_IMAGE_NAME" \
              --argjson matrix_data "$MATRIX_RESULT" \
              '{
                image_name: $image_name,
                matrix: $matrix_data.matrix,
                architectures: $matrix_data.architectures
              }')

            echo "=== Preparation Complete ===" >&2
            echo "" >&2
            echo "Results:" >&2
            echo "$RESULT" | ${pkgs.jq}/bin/jq -C '.' >&2
            echo "" >&2

            # Output for GitHub Actions
            echo "$RESULT"
          '');
        };
      }
    );
}
