#!/usr/bin/env python3
"""Recognize a Sudoku puzzle from an image using OpenCV and a TFLite model.

Thin wrapper around :func:`sudoku_vision.pipeline.recognize_image_file`. The
shared pipeline is used by both the CLI (``sudoku-vision recognize``) and the
FastAPI service (``/recognize``).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sudoku_vision.pipeline import recognize_image_file


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--board-size", type=int, default=900)
    parser.add_argument(
        "--corners",
        type=Path,
        help="Optional JSON file with manual 4-corner [[x, y], ...] override",
    )
    args = parser.parse_args()

    corners = None
    if args.corners:
        corners_data = json.loads(args.corners.read_text(encoding="utf-8"))
        corners = np.asarray(corners_data, dtype=np.float32)
        if corners.shape != (4, 2):
            raise SystemExit("--corners JSON must be a 4x2 array")

    payload = recognize_image_file(
        args.image,
        model_path=args.model,
        corners=corners,
        board_size=args.board_size,
    )
    serialized = json.dumps(payload, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(serialized, encoding="utf-8")
    else:
        print(serialized)


if __name__ == "__main__":
    main()
