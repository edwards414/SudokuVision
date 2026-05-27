"""Contract test for the project Makefile.

The Makefile is the canonical entry point for shared dev workflows. We assert
that the targets a contributor (or CI) is going to type by hand exist, are
declared phony, and remain documented in the help output."""

from __future__ import annotations

import re
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_TARGETS = (
    "help",
    "install",
    "install-vision",
    "install-train",
    "install-api",
    "test",
    "lint",
    "train",
    "export",
    "evaluate",
    "api",
    "docker-build",
    "docker-test",
    "compose-up",
    "compose-down",
    "compose-rtsp-up",
    "stream-host",
    "stream-rtsp",
    "flutter-test",
    "flutter-analyze",
    "screenshots",
    "clean",
)


def _read_makefile() -> str:
    path = ROOT / "Makefile"
    assert path.exists(), "Makefile missing at repo root"
    return path.read_text(encoding="utf-8")


def test_makefile_defines_required_targets():
    text = _read_makefile()
    rule_pattern = re.compile(r"^([A-Za-z0-9_.\-]+):", re.MULTILINE)
    defined = set(rule_pattern.findall(text))

    for target in REQUIRED_TARGETS:
        assert target in defined, f"Makefile missing target: {target}"


def test_makefile_declares_targets_phony():
    text = _read_makefile()
    assert ".PHONY:" in text
    # Collect every .PHONY block, including ones split across multiple lines
    # with trailing backslashes.
    phony_targets: set[str] = set()
    block = re.compile(r"^\.PHONY:\s*((?:.*?\\\n)*.*?)$", re.MULTILINE | re.DOTALL)
    for match in block.finditer(text):
        joined = match.group(1).replace("\\\n", " ")
        phony_targets.update(joined.split())
    for target in REQUIRED_TARGETS:
        assert target in phony_targets, f".PHONY missing: {target}"


def test_makefile_help_lists_targets():
    """`make help` should print at least one line per required target.

    This catches drift between the Makefile and its self-documentation."""

    completed = subprocess.run(
        ["make", "-s", "help"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode == 127:  # make not installed in this environment
        import pytest

        pytest.skip("make is not installed")
    assert completed.returncode == 0, completed.stderr
    output = completed.stdout
    for target in REQUIRED_TARGETS:
        assert target in output, f"`make help` missing target: {target}"
