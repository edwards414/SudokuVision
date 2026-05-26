"""Unit tests for the shared image → grid → solve pipeline."""

from __future__ import annotations

import numpy as np
import pytest

from sudoku_vision.pipeline import recognize_image_array, solve_grid
from sudoku_vision.recognizer import DigitRecognizer

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


class _ConstantClassifier:
    """Predict the digit dictated by the image's top-left pixel value.

    The pipeline ultimately calls ``DigitRecognizer.recognize`` which already
    has direct tests; this fake gives ``recognize_image_array`` something to
    chew on without needing TensorFlow or a real model file.
    """

    def __init__(self) -> None:
        # Always predicts class 0 (empty) with high confidence.
        self._probabilities = np.zeros(10, dtype=np.float32)
        self._probabilities[0] = 1.0

    def predict_proba(self, model_input: np.ndarray) -> np.ndarray:
        return self._probabilities


def test_solve_grid_returns_solved_for_valid_puzzle() -> None:
    payload = solve_grid(VALID_PUZZLE)
    assert payload["validation"]["is_valid"] is True
    assert payload["solve"]["status"] == "solved"
    assert payload["solve"]["has_unique_solution"] is True
    assert payload["solve"]["solution"][8][8] == 9


def test_solve_grid_returns_invalid_puzzle_for_bad_row() -> None:
    bad = [list(row) for row in VALID_PUZZLE]
    bad[0][0] = 7  # duplicate of (0, 4)
    payload = solve_grid(bad)
    assert payload["validation"]["is_valid"] is False
    assert payload["solve"] is None


def test_recognize_image_array_honours_manual_corners() -> None:
    pytest.importorskip("cv2")

    image = np.full((400, 400, 3), 255, dtype=np.uint8)
    recognizer = DigitRecognizer(classifier=_ConstantClassifier())

    corners = np.array(
        [[10, 10], [390, 10], [390, 390], [10, 390]],
        dtype=np.float32,
    )
    payload = recognize_image_array(
        image,
        recognizer=recognizer,
        corners=corners,
        board_size=180,
    )
    assert payload["grid"] == [[0] * 9 for _ in range(9)]
    assert payload["board_corners"][0] == pytest.approx([10.0, 10.0])
    assert payload["status"] == "multiple_solutions"  # empty board has many solves
