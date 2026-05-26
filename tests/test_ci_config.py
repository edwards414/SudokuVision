from pathlib import Path
import tomllib


ROOT = Path(__file__).resolve().parents[1]


def test_dockerfile_defines_test_and_runtime_image_contract():
    dockerfile = ROOT / "Dockerfile"

    assert dockerfile.exists()
    text = dockerfile.read_text(encoding="utf-8")

    assert "FROM python:3.12-slim AS base" in text
    assert "AS test" in text
    assert "AS runtime" in text
    assert "pytest" in text
    assert "python -m sudoku_vision.cli health" in text
    assert "CMD" in text


def test_ghcr_workflow_builds_validates_and_publishes_image():
    workflow = ROOT / ".github" / "workflows" / "container.yml"

    assert workflow.exists()
    text = workflow.read_text(encoding="utf-8")

    assert "packages: write" in text
    assert "id: image" in text
    assert "${GITHUB_REPOSITORY,,}" in text
    assert "docker/login-action" in text
    assert "docker/metadata-action" in text
    assert "docker/build-push-action" in text
    assert "ghcr.io/${GITHUB_REPOSITORY,,}" in text
    assert "${{ steps.image.outputs.name }}" in text
    assert "target: test" in text
    assert "push: true" in text
    assert "docker run --rm" in text
    assert "python -m sudoku_vision.cli health" in text


def test_dockerignore_keeps_build_context_small():
    dockerignore = ROOT / ".dockerignore"

    assert dockerignore.exists()
    text = dockerignore.read_text(encoding="utf-8")

    assert ".git" in text
    assert "__pycache__" in text
    assert ".pytest_cache" in text
    assert "artifacts" in text


def test_vision_extra_uses_windows_camera_capable_opencv_package():
    pyproject = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))

    vision_deps = pyproject["project"]["optional-dependencies"]["vision"]

    assert 'opencv-python>=4.8; platform_system == "Windows"' in vision_deps
    assert 'opencv-python-headless>=4.8; platform_system != "Windows"' in vision_deps


def test_setuptools_package_discovery_excludes_flutter_app_directory():
    pyproject = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))

    package_finder = pyproject["tool"]["setuptools"]["packages"]["find"]

    assert package_finder["include"] == ["sudoku_vision*"]
    assert "app*" in package_finder["exclude"]
