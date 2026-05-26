"""End-to-end integration: synthesise a printed-digit Sudoku image,
detect the board, split cells, recognise digits with a fake classifier, and
solve."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest


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


def _render_board(grid: list[list[int]], cell_px: int = 60, margin: int = 30) -> np.ndarray:
    pytest.importorskip("PIL")
    from PIL import Image, ImageDraw, ImageFont

    board_px = 9 * cell_px
    image = Image.new("L", (board_px + 2 * margin, board_px + 2 * margin), color=255)
    draw = ImageDraw.Draw(image)

    # Heavy borders + light gridlines, drawn so cells stay perfectly square.
    for i in range(10):
        x = margin + i * cell_px
        y = margin + i * cell_px
        thickness = 4 if i % 3 == 0 else 1
        draw.line([(x, margin), (x, margin + board_px)], fill=0, width=thickness)
        draw.line([(margin, y), (margin + board_px, y)], fill=0, width=thickness)

    font_candidates = [
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    font = None
    for candidate in font_candidates:
        if Path(candidate).exists():
            try:
                font = ImageFont.truetype(candidate, int(cell_px * 0.6))
                break
            except OSError:
                continue
    if font is None:
        font = ImageFont.load_default()

    for r, row in enumerate(grid):
        for c, value in enumerate(row):
            if value == 0:
                continue
            text = str(value)
            bbox = draw.textbbox((0, 0), text, font=font)
            tw = bbox[2] - bbox[0]
            th = bbox[3] - bbox[1]
            cx = margin + c * cell_px + cell_px // 2
            cy = margin + r * cell_px + cell_px // 2
            draw.text(
                (cx - tw // 2 - bbox[0], cy - th // 2 - bbox[1]),
                text,
                font=font,
                fill=0,
            )

    return np.asarray(image)


class _LookupClassifier:
    """Returns probabilities matching the known grid at a given (row, col).

    The pipeline calls ``recognize(cells)`` which iterates row-major. We track
    a counter so each call corresponds to the next (row, col) in the grid.
    """

    def __init__(self, grid: list[list[int]]) -> None:
        self._grid = [v for row in grid for v in row]
        self._cursor = 0

    def predict_proba(self, model_input: np.ndarray) -> np.ndarray:
        value = self._grid[self._cursor]
        self._cursor += 1
        probabilities = np.zeros(10, dtype=np.float32)
        probabilities[value] = 0.98
        # spread the residual mass to keep softmax-ish shape
        for i in range(10):
            if i != value:
                probabilities[i] = 0.02 / 9
        return probabilities


def test_end_to_end_pipeline_recovers_known_puzzle() -> None:
    pytest.importorskip("cv2")
    pytest.importorskip("PIL")

    from sudoku_vision.pipeline import recognize_image_array
    from sudoku_vision.recognizer import DigitRecognizer

    gray = _render_board(VALID_PUZZLE)
    bgr = np.stack([gray, gray, gray], axis=-1)
    recognizer = DigitRecognizer(classifier=_LookupClassifier(VALID_PUZZLE))

    payload = recognize_image_array(bgr, recognizer=recognizer)

    assert payload["grid"] == VALID_PUZZLE
    assert payload["validation"]["is_valid"] is True
    assert payload["solve"]["status"] == "solved"
    assert payload["status"] == "solved"
    assert payload["solve"]["solution"][0][2] == 4
