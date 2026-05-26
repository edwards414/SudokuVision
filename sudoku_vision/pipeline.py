"""Image → grid → solve pipeline shared by the CLI, API, and scripts."""

from __future__ import annotations

from dataclasses import asdict
from pathlib import Path
from typing import Any

import numpy as np

from sudoku_vision.board import extract_board, warp_board
from sudoku_vision.errors import OptionalDependencyError
from sudoku_vision.preprocessing import split_board_cells
from sudoku_vision.recognizer import DigitRecognizer
from sudoku_vision.solver import Grid, SolveResult, solve_unique, validate_grid


def solve_grid(grid: Grid) -> dict[str, Any]:
    """Validate and solve a 9x9 grid, returning a JSON-serialisable dict."""

    validation = validate_grid(grid)
    payload: dict[str, Any] = {
        "validation": {
            "is_valid": validation.is_valid,
            "issues": [asdict(issue) for issue in validation.issues],
        },
        "solve": None,
    }
    if validation.is_valid:
        result: SolveResult = solve_unique(grid)
        payload["solve"] = _serialize_solve(result)
    return payload


def _serialize_solve(result: SolveResult) -> dict[str, Any]:
    return {
        "status": result.status,
        "has_unique_solution": result.has_unique_solution,
        "solution": result.solution,
        "message": result.message,
        "issues": [asdict(issue) for issue in (result.issues or [])],
    }


def recognize_image_array(
    image: np.ndarray,
    *,
    recognizer: DigitRecognizer,
    corners: np.ndarray | None = None,
    board_size: int = 900,
) -> dict[str, Any]:
    """Run the full image → grid → solve pipeline on a decoded image array.

    When ``corners`` is provided it overrides the auto-detect step, which is the
    fallback used by the manual 4-corner correction flow.
    """

    if corners is not None:
        warped = warp_board(image, np.asarray(corners, dtype=np.float32), output_size=board_size)
        used_corners = np.asarray(corners, dtype=np.float32)
    else:
        warped, used_corners = extract_board(image, output_size=board_size)

    cells = split_board_cells(warped)
    recognition = recognizer.recognize(cells)
    payload = recognition.to_dict()
    payload["board_corners"] = used_corners.tolist()
    solve_payload = solve_grid(recognition.grid)
    payload["validation"] = solve_payload["validation"]
    payload["solve"] = solve_payload["solve"]
    payload["status"] = _status_from_solve(solve_payload, recognition.low_confidence_cells)
    return payload


def _status_from_solve(
    solve_payload: dict[str, Any],
    low_confidence_cells: list[dict[str, int | float]],
) -> str:
    if not solve_payload["validation"]["is_valid"]:
        return "invalid_puzzle"
    if solve_payload["solve"] is None:
        return "needs_review"
    if low_confidence_cells:
        return "needs_review"
    return solve_payload["solve"]["status"]


def recognize_image_file(
    image_path: Path,
    *,
    model_path: Path,
    corners: np.ndarray | None = None,
    board_size: int = 900,
) -> dict[str, Any]:
    """Decode the image with OpenCV and run the recognition pipeline."""

    try:
        import cv2  # type: ignore
    except ModuleNotFoundError as exc:
        raise OptionalDependencyError("opencv-python", "image decoding") from exc

    image = cv2.imread(str(image_path))
    if image is None:
        raise FileNotFoundError(f"Could not read image: {image_path}")

    recognizer = DigitRecognizer(model_path=str(model_path))
    return recognize_image_array(
        image,
        recognizer=recognizer,
        corners=corners,
        board_size=board_size,
    )
