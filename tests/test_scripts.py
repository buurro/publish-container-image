"""
Tests for workflow helper apps.

These tests verify that the Nix apps work correctly
and produce expected outputs.
"""

import json
import subprocess

import pytest


def run_nix_app(app_name: str, *args: str) -> subprocess.CompletedProcess:
    """Run a Nix app with given arguments."""
    result = subprocess.run(
        ["nix", "run", f".#{app_name}", "--", *args],
        capture_output=True,
        text=True,
    )
    return result


class TestDetermineImageName:
    """Test determine-image-name Nix app."""

    def test_uses_custom_image_name_when_provided(self):
        """Should use custom image name when provided."""
        result = run_nix_app(
            "determine-image-name",
            "custom/image-name",  # image_name
            ".#containerImage",   # nix_attr
            "ghcr.io",           # registry
            "buurro/fallback",   # github_repository
        )
        assert result.returncode == 0
        assert result.stdout.strip() == "custom/image-name"

    def test_extracts_from_nix_when_no_custom_name(self):
        """Should extract image name from Nix package when not provided."""
        result = run_nix_app(
            "determine-image-name",
            "",                  # image_name (empty)
            ".#containerImage",  # nix_attr
            "ghcr.io",          # registry
            "buurro/publish-container-image",  # github_repository
        )
        assert result.returncode == 0
        assert result.stdout.strip() == "buurro/publish-container-image"

    def test_strips_registry_prefix_from_nix_name(self):
        """Should strip registry prefix from Nix imageName."""
        # Our actual flake has name = "ghcr.io/buurro/publish-container-image"
        # The script should extract just "buurro/publish-container-image"
        result = run_nix_app(
            "determine-image-name",
            "",                  # image_name (empty)
            ".#containerImage",  # nix_attr
            "ghcr.io",          # registry
            "buurro/publish-container-image",  # github_repository
        )
        assert result.returncode == 0
        # Should not contain registry prefix
        output = result.stdout.strip()
        assert not output.startswith("ghcr.io/")
        assert output == "buurro/publish-container-image"


class TestPrepareMatrix:
    """Test prepare-matrix Nix app."""

    def test_space_separated_architectures(self):
        """Should parse space-separated architectures."""
        result = run_nix_app(
            "prepare-matrix",
            "amd64 arm64",  # architectures
            "24.04",        # ubuntu_version
        )
        assert result.returncode == 0

        output = json.loads(result.stdout)
        assert "matrix" in output
        assert "architectures" in output
        assert len(output["matrix"]["include"]) == 2
        assert output["architectures"] == ["amd64", "arm64"]

        # Check matrix entries
        amd64_entry = next(e for e in output["matrix"]["include"] if e["arch"] == "amd64")
        assert amd64_entry["runner"] == "ubuntu-24.04"

        arm64_entry = next(e for e in output["matrix"]["include"] if e["arch"] == "arm64")
        assert arm64_entry["runner"] == "ubuntu-24.04-arm"

    def test_comma_separated_architectures(self):
        """Should parse comma-separated architectures."""
        result = run_nix_app(
            "prepare-matrix",
            "amd64,arm64",  # architectures
            "24.04",        # ubuntu_version
        )
        assert result.returncode == 0

        output = json.loads(result.stdout)
        assert len(output["matrix"]["include"]) == 2
        assert output["architectures"] == ["amd64", "arm64"]

    def test_mixed_separators(self):
        """Should handle mixed comma and space separators."""
        result = run_nix_app(
            "prepare-matrix",
            "amd64, arm64",  # architectures (comma + space)
            "24.04",         # ubuntu_version
        )
        assert result.returncode == 0

        output = json.loads(result.stdout)
        assert len(output["matrix"]["include"]) == 2
        assert output["architectures"] == ["amd64", "arm64"]

    def test_single_architecture(self):
        """Should work with single architecture."""
        result = run_nix_app(
            "prepare-matrix",
            "amd64",  # architectures
            "24.04",  # ubuntu_version
        )
        assert result.returncode == 0

        output = json.loads(result.stdout)
        assert len(output["matrix"]["include"]) == 1
        assert output["architectures"] == ["amd64"]
        assert output["matrix"]["include"][0]["arch"] == "amd64"
        assert output["matrix"]["include"][0]["runner"] == "ubuntu-24.04"

    def test_different_ubuntu_version(self):
        """Should use correct runner for different Ubuntu versions."""
        result = run_nix_app(
            "prepare-matrix",
            "amd64",  # architectures
            "22.04",  # ubuntu_version
        )
        assert result.returncode == 0

        output = json.loads(result.stdout)
        assert output["matrix"]["include"][0]["runner"] == "ubuntu-22.04"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
