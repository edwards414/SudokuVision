#!/usr/bin/env python3
"""Recognize a Sudoku puzzle from an image using OpenCV and a TFLite model."""

from __future__ import annotations

import argparse
from dataclasses import asdict
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sudoku_vision.board import extract_board
from sudoku_vision.preprocessing import split_board_cells
from sudoku_vision.recognizer import DigitRecognizer
from sudoku_vision.solver import solve_unique, validate_grid


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--board-size", type=int, default=900)
    args = parser.parse_args()

    import cv2  # type: ignore

    image = cv2.imread(str(args.image))
    if image is None:
        raise SystemExit(f"Could not read image: {args.image}")

    board, corners = extract_board(image, output_size=args.board_size)
    cells = split_board_cells(board)
    recognizer = DigitRecognizer(model_path=args.model)
    recognition = recognizer.recognize(cells)
    validation = validate_grid(recognition.grid)
    solve_result = solve_unique(recognition.grid) if validation.is_valid else None

    payload = recognition.to_dict()
    payload["board_corners"] = corners.tolist()
    payload["validation"] = {
        "is_valid": validation.is_valid,
        "issues": [asdict(issue) for issue in validation.issues],
    }
    payload["solve"] = asdict(solve_result) if solve_result else None

    serialized = json.dumps(payload, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(serialized, encoding="utf-8")
    else:
        print(serialized)


if __name__ == "__main__":
    main()
