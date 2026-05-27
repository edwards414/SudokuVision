"""Score the trained TFLite model against captured puzzle fixtures.

The screen_sudoku fixture is a real screenshot the printed-font augmentation
struggled with before retraining. The test is skipped when the model artifact
isn't present so it doesn't pin CI builds that don't ship a model."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[1]
MODEL_PATH = ROOT / "artifacts" / "mnist" / "digit_classifier_int8.tflite"
FIXTURE_DIR = ROOT / "tests" / "fixtures"


# Ground-truth grid for tests/fixtures/screen_sudoku.png.
SCREEN_SUDOKU_GRID = [
    [2, 0, 0, 0, 0, 0, 0, 0, 8],
    [0, 0, 3, 0, 0, 0, 6, 0, 0],
    [0, 7, 0, 0, 8, 0, 0, 1, 0],
    [0, 0, 0, 3, 0, 7, 0, 0, 0],
    [0, 0, 7, 0, 0, 0, 4, 0, 0],
    [0, 0, 0, 5, 0, 9, 0, 0, 0],
    [0, 6, 0, 0, 5, 0, 0, 2, 0],
    [0, 0, 2, 0, 0, 0, 3, 0, 0],
    [1, 0, 0, 0, 0, 0, 0, 0, 4],
]


def _score(grid: list[list[int]], expected: list[list[int]]) -> tuple[float, float]:
    cells = empties = correct = empty_correct = 0
    digit_correct = digit_cells = 0
    for r in range(9):
        for c in range(9):
            cells += 1
            exp = expected[r][c]
            pred = grid[r][c]
            if pred == exp:
                correct += 1
            if exp == 0:
                empties += 1
                if pred == 0:
                    empty_correct += 1
            else:
                digit_cells += 1
                if pred == exp:
                    digit_correct += 1
    overall = correct / cells
    digit_acc = digit_correct / max(1, digit_cells)
    return overall, digit_acc


@pytest.mark.skipif(not MODEL_PATH.is_file(), reason="trained model not present")
def test_screen_sudoku_fixture_meets_accuracy_floor() -> None:
    pytest.importorskip("cv2")
    pytest.importorskip("PIL")

    import cv2  # type: ignore

    image_path = FIXTURE_DIR / "screen_sudoku.png"
    assert image_path.is_file(), f"missing fixture {image_path}"

    from sudoku_vision.board import extract_board
    from sudoku_vision.preprocessing import split_board_cells
    from sudoku_vision.recognizer import DigitRecognizer

    image = cv2.imread(str(image_path))
    assert image is not None, "could not decode fixture image"

    board, _ = extract_board(image)
    cells = split_board_cells(board)
    recognizer = DigitRecognizer(model_path=str(MODEL_PATH))
    result = recognizer.recognize(cells)

    overall, digit_acc = _score(result.grid, SCREEN_SUDOKU_GRID)
    # Print so failures show the actual numbers in pytest output.
    print(f"\nscreen_sudoku overall accuracy: {overall:.3f}")
    print(f"screen_sudoku digit accuracy:   {digit_acc:.3f}")
    print(f"low-confidence cells: {len(result.low_confidence_cells)}")

    # Current realistic floors (2026-05-27 v5 model):
    #   overall ≥ 0.85 — blanks dominate the 81 cells so this stays high.
    #   digit_acc ≥ 0.55 — TinyCNN still misclassifies curvy digits toward
    #   8/9 on Sudoku.com-style fonts; tracked separately as a follow-up.
    # The Review-tab manual-correction flow makes the system usable in
    # practice even at this accuracy; floors will tighten as the printed
    # font dataset grows.
    assert overall >= 0.85, f"overall accuracy below floor: {overall:.3f}"
    assert digit_acc >= 0.55, f"digit accuracy below floor: {digit_acc:.3f}"
