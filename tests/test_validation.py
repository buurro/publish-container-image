"""
Security validation tests for input validation.

These tests ensure that malicious inputs are properly blocked
and that valid inputs pass through correctly.
"""

import subprocess

import pytest


def run_validation(
    nix_attr: str = "",
    registry: str = "",
    image_name: str = "",
    architectures: str = "",
    ubuntu_version: str = "",
) -> subprocess.CompletedProcess:
    """Run the validation Nix app with given inputs."""
    result = subprocess.run(
        ["nix", "run", ".#validate-inputs", "--", nix_attr, registry, image_name, architectures, ubuntu_version],
        capture_output=True,
        text=True,
    )
    return result


class TestValidInputs:
    """Test that valid inputs are accepted."""

    def test_all_valid_inputs(self):
        """Valid inputs should pass validation."""
        result = run_validation(
            nix_attr=".#containerImage",
            registry="ghcr.io",
            image_name="buurro/my-app",
            architectures="amd64 arm64",
            ubuntu_version="24.04",
        )
        assert result.returncode == 0, f"Validation failed: {result.stderr}"
        assert "All inputs validated successfully" in result.stderr

    def test_minimal_valid_inputs(self):
        """Validation should work with minimal inputs."""
        result = run_validation(nix_attr=".#containerImage")
        assert result.returncode == 0
        assert "All inputs validated successfully" in result.stderr

    def test_single_architecture(self):
        """Single architecture should be valid."""
        result = run_validation(architectures="amd64")
        assert result.returncode == 0

    def test_comma_separated_architectures(self):
        """Comma-separated architectures should be valid."""
        result = run_validation(architectures="amd64,arm64")
        assert result.returncode == 0


class TestCommandInjection:
    """Test that command injection attempts are blocked."""

    @pytest.mark.parametrize(
        "malicious_input",
        [
            ".#containerImage; whoami",
            ".#containerImage && ls",
            ".#containerImage | cat",
            ".#containerImage & bg",
            ".#containerImage$(id)",
            ".#containerImage`id`",
        ],
    )
    def test_shell_metacharacters_blocked(self, malicious_input):
        """Shell metacharacters in nix-flake-attr should be blocked."""
        result = run_validation(nix_attr=malicious_input)
        assert result.returncode != 0, f"Should have blocked: {malicious_input}"
        assert "invalid characters" in result.stderr or "shell metacharacters" in result.stderr

    def test_valid_nix_attr_with_special_chars(self):
        """Valid special characters should be allowed."""
        valid_attrs = [
            ".#containerImage",
            ".#packages.x86_64-linux.containerImage",
            "/nix/store/abc-def/containerImage",
            ".#my-package_v2",
        ]
        for attr in valid_attrs:
            result = run_validation(nix_attr=attr)
            assert result.returncode == 0, f"Should have allowed: {attr}"


class TestPathTraversal:
    """Test that path traversal attempts are blocked."""

    @pytest.mark.parametrize(
        "malicious_path",
        [
            "../../../etc/passwd",
            "../../etc/shadow",
            "foo/../../../bar",
            "legitimate/../../../malicious",
        ],
    )
    def test_path_traversal_blocked(self, malicious_path):
        """Path traversal in image-name should be blocked."""
        result = run_validation(image_name=malicious_path)
        assert result.returncode != 0, f"Should have blocked: {malicious_path}"
        assert "path traversal" in result.stderr

    def test_valid_image_names(self):
        """Valid image names should be allowed."""
        valid_names = [
            "myapp",
            "my-app",
            "my_app",
            "myorg/myapp",
            "registry.io/myorg/myapp",
            "my.app/with.dots",
        ]
        for name in valid_names:
            result = run_validation(image_name=name)
            assert result.returncode == 0, f"Should have allowed: {name}"


class TestRegistryValidation:
    """Test registry hostname validation."""

    def test_known_registries_allowed(self):
        """Known safe registries should be allowed."""
        known_registries = [
            "ghcr.io",
            "docker.io",
            "quay.io",
            "gcr.io",
        ]
        for registry in known_registries:
            result = run_validation(registry=registry)
            assert result.returncode == 0, f"Should have allowed: {registry}"

    def test_unknown_registry_warns_but_allows(self):
        """Unknown registries should warn but still allow."""
        result = run_validation(registry="untrusted.example.com")
        assert result.returncode == 0, "Unknown registry should be allowed with warning"
        assert "not in the known safe list" in result.stderr

    @pytest.mark.parametrize(
        "invalid_registry",
        [
            "evil.com; whoami",
            "registry|command",
            "registry`id`",
            "registry$VAR",
        ],
    )
    def test_invalid_registry_blocked(self, invalid_registry):
        """Invalid registry hostnames should be blocked."""
        result = run_validation(registry=invalid_registry)
        assert result.returncode != 0, f"Should have blocked: {invalid_registry}"


class TestArchitectureValidation:
    """Test architecture validation."""

    @pytest.mark.parametrize(
        "valid_arch",
        [
            "amd64",
            "arm64",
            "arm",
            "386",
            "ppc64le",
            "s390x",
            "amd64 arm64",
            "amd64,arm64",
            "amd64, arm64",  # with spaces
        ],
    )
    def test_known_architectures_allowed(self, valid_arch):
        """Known architectures should be allowed."""
        result = run_validation(architectures=valid_arch)
        assert result.returncode == 0, f"Should have allowed: {valid_arch}"

    @pytest.mark.parametrize(
        "invalid_arch",
        [
            "x86",
            "badarch",
            "evil-arch",
            "amd64; whoami",
        ],
    )
    def test_unknown_architectures_blocked(self, invalid_arch):
        """Unknown or malicious architectures should be blocked."""
        result = run_validation(architectures=invalid_arch)
        assert result.returncode != 0, f"Should have blocked: {invalid_arch}"
        assert "Unknown architecture" in result.stderr


class TestUbuntuVersion:
    """Test Ubuntu version validation."""

    @pytest.mark.parametrize("valid_version", ["20.04", "22.04", "24.04"])
    def test_known_versions_allowed(self, valid_version):
        """Known Ubuntu LTS versions should be allowed."""
        result = run_validation(ubuntu_version=valid_version)
        assert result.returncode == 0, f"Should have allowed: {valid_version}"

    @pytest.mark.parametrize(
        "invalid_version",
        [
            "18.04",  # EOL
            "19.10",  # Not LTS
            "99.99",  # Doesn't exist
            "latest",  # Not a version number
        ],
    )
    def test_unknown_versions_blocked(self, invalid_version):
        """Unknown Ubuntu versions should be blocked."""
        result = run_validation(ubuntu_version=invalid_version)
        assert result.returncode != 0, f"Should have blocked: {invalid_version}"
        assert "Unknown ubuntu-version" in result.stderr


class TestImageNameRules:
    """Test specific image name validation rules."""

    @pytest.mark.parametrize(
        "invalid_name",
        [
            "MyApp",  # Uppercase
            "My-App",  # Uppercase
            "myapp/MyImage",  # Uppercase in second part
            "/leading-slash",
            "trailing-slash/",
            "special!chars",
            "special@chars",
        ],
    )
    def test_invalid_image_names_blocked(self, invalid_name):
        """Invalid image name formats should be blocked."""
        result = run_validation(image_name=invalid_name)
        assert result.returncode != 0, f"Should have blocked: {invalid_name}"


class TestNixFlakeAttrRules:
    """Test specific nix-flake-attr validation rules."""

    def test_must_start_with_hash_or_slash(self):
        """Nix flake attr must start with .# or /."""
        invalid_attrs = [
            "containerImage",  # No prefix
            "#containerImage",  # Missing dot
            "packages.containerImage",  # Missing .#
        ]
        for attr in invalid_attrs:
            result = run_validation(nix_attr=attr)
            assert result.returncode != 0, f"Should have blocked: {attr}"
            assert "must start with" in result.stderr

    def test_valid_prefixes_allowed(self):
        """Valid prefixes should be allowed."""
        valid_attrs = [
            ".#containerImage",
            "/nix/store/path",
        ]
        for attr in valid_attrs:
            result = run_validation(nix_attr=attr)
            assert result.returncode == 0, f"Should have allowed: {attr}"


class TestEdgeCases:
    """Test edge cases and boundary conditions."""

    def test_empty_inputs_allowed(self):
        """Empty inputs should be allowed (workflow will use defaults)."""
        result = run_validation()
        assert result.returncode == 0

    def test_whitespace_only_treated_as_empty(self):
        """Whitespace-only inputs should be treated as empty."""
        result = run_validation(image_name="   ")
        # Should either pass (treated as empty) or fail with specific error
        # Current implementation treats as empty, so should pass
        assert result.returncode == 0 or "invalid characters" in result.stderr


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
