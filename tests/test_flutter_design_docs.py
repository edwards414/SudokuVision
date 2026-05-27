from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_flutter_apple_design_guide_exists_and_names_required_cupertino_patterns():
    guide = ROOT / "docs" / "FLUTTER_APPLE_DESIGN.md"

    assert guide.exists()
    text = guide.read_text(encoding="utf-8")

    assert "CupertinoApp" in text
    assert "CupertinoPageScaffold" in text
    assert "CupertinoNavigationBar" in text
    assert "CupertinoColors" in text
    assert "Dynamic Type" in text
    assert "SafeArea" in text
    assert "低信心" in text
    assert "Apple Human Interface Guidelines" in text
    assert "同一個相機視窗" in text


def test_readme_links_flutter_apple_design_guide():
    readme = (ROOT / "README.md").read_text(encoding="utf-8")

    assert "Flutter Apple Design" in readme
    assert "docs/FLUTTER_APPLE_DESIGN.md" in readme


def test_spec_records_flutter_apple_design_requirement():
    spec = (ROOT / "SPEC.md").read_text(encoding="utf-8")

    assert "Flutter Apple Design" in spec
    assert "Cupertino" in spec
