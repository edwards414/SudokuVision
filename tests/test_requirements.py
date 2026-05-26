from pathlib import Path
import tomllib


ROOT = Path(__file__).resolve().parents[1]


def _read_requirements(path: Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def test_requirements_files_exist_for_common_install_modes():
    assert (ROOT / "requirements.txt").exists()
    assert (ROOT / "requirements-dev.txt").exists()
    assert (ROOT / "requirements-vision.txt").exists()
    assert (ROOT / "requirements-train.txt").exists()
    assert (ROOT / "requirements-all.txt").exists()


def test_requirements_match_pyproject_dependency_groups():
    pyproject = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))

    assert _read_requirements(ROOT / "requirements.txt") == pyproject["project"]["dependencies"]
    assert _read_requirements(ROOT / "requirements-dev.txt") == (
        pyproject["project"]["dependencies"]
        + pyproject["project"]["optional-dependencies"]["dev"]
    )
    assert _read_requirements(ROOT / "requirements-vision.txt") == (
        pyproject["project"]["dependencies"]
        + pyproject["project"]["optional-dependencies"]["vision"]
    )
    assert _read_requirements(ROOT / "requirements-train.txt") == (
        pyproject["project"]["dependencies"]
        + pyproject["project"]["optional-dependencies"]["train"]
    )
