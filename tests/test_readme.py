from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_readme_stays_clean_and_points_to_deeper_docs():
    readme = ROOT / "README.md"
    text = readme.read_text(encoding="utf-8")

    assert len(text.splitlines()) <= 220

    for required_text in [
        "Quick Start",
        "Common Commands",
        "Camera",
        "Docker / GHCR",
        "Flutter Apple Design",
        "TinyCNN Model Result Spec",
        "docs/TDD_WORKFLOW.md",
        "docs/FLUTTER_APPLE_DESIGN.md",
        "docs/TINY_CNN_MODEL_RESULT_SPEC.md",
    ]:
        assert required_text in text
