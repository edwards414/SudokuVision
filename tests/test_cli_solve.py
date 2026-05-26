"""CLI `solve` subcommand contract."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

VALID_PUZZLE = [
    [5, 3, 0, 0, 7, 0, 0, 0, 0],
    [6, 0, 0, 1, 9, 5, 0, 0, 0],
    [0, 9, 8, 0, 0, 0, 0, 6, 0],
    [8, 0, 0, 0, 6, 0, 0, 0, 3],
    [4, 0, 0, 8, 0, 3, 0, 0, 1],
    [7, 0, 0, 0, 2, 0, 0, 0, 6],
    [0, 6, 0, 0, 0, 0, 2, 8, 0],
    [0, 0, 0, 4, 1, 9, 0, 0, 5],
    [0, 0, 0, 0, 8, 0, 0, 7, 9],
]


def _run(args, stdin_text=None):
    return subprocess.run(
        [sys.executable, "-m", "sudoku_vision.cli", *args],
        check=False,
        capture_output=True,
        text=True,
        input=stdin_text,
    )


def test_cli_solve_reads_grid_from_stdin_and_returns_solved_status():
    completed = _run(["solve", "--grid", "-"], stdin_text=json.dumps(VALID_PUZZLE))

    assert completed.returncode == 0, completed.stderr
    payload = json.loads(completed.stdout)
    assert payload["validation"]["is_valid"] is True
    assert payload["solve"]["status"] == "solved"
    assert payload["solve"]["has_unique_solution"] is True
    assert payload["solve"]["solution"][0][2] == 4


def test_cli_solve_reads_grid_from_file(tmp_path: Path):
    grid_path = tmp_path / "puzzle.json"
    grid_path.write_text(json.dumps(VALID_PUZZLE), encoding="utf-8")

    completed = _run(["solve", "--grid", str(grid_path)])

    assert completed.returncode == 0, completed.stderr
    payload = json.loads(completed.stdout)
    assert payload["solve"]["status"] == "solved"


def test_cli_solve_returns_invalid_puzzle_for_duplicate_row():
    bad = [list(row) for row in VALID_PUZZLE]
    bad[0][0] = 7  # duplicate of (0,4)
    completed = _run(["solve", "--grid", "-"], stdin_text=json.dumps(bad))

    assert completed.returncode == 0, completed.stderr
    payload = json.loads(completed.stdout)
    assert payload["validation"]["is_valid"] is False
    assert payload["solve"] is None


def test_cli_solve_returns_multiple_solutions_for_empty_grid():
    empty = [[0] * 9 for _ in range(9)]
    completed = _run(["solve", "--grid", "-"], stdin_text=json.dumps(empty))

    assert completed.returncode == 0, completed.stderr
    payload = json.loads(completed.stdout)
    assert payload["solve"]["status"] == "multiple_solutions"
    assert payload["solve"]["has_unique_solution"] is False
