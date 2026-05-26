"""FastAPI service exposing /health, /solve, /recognize."""

from __future__ import annotations

import io
import json
import os
from pathlib import Path
from typing import Any

import numpy as np

try:
    from fastapi import FastAPI, File, Form, HTTPException, UploadFile
    from fastapi.middleware.cors import CORSMiddleware
    from pydantic import BaseModel, Field
except ModuleNotFoundError as exc:  # pragma: no cover - import-time guard
    raise RuntimeError(
        "FastAPI dependencies missing. Install with `pip install -e .[api]`."
    ) from exc

from sudoku_vision.pipeline import recognize_image_array, solve_grid
from sudoku_vision.recognizer import DigitRecognizer


class SolveRequest(BaseModel):
    grid: list[list[int]] = Field(
        ...,
        description="9x9 array of integers, 0 = empty, 1-9 = given.",
        min_length=9,
        max_length=9,
    )


def _validate_grid_shape(grid: list[list[int]]) -> None:
    if any(len(row) != 9 for row in grid):
        raise HTTPException(status_code=422, detail="Each row must have 9 columns")


def build_app(
    *,
    model_path: str | os.PathLike[str] | None = None,
    allow_origins: list[str] | None = None,
) -> FastAPI:
    """Build the FastAPI app. ``model_path`` defaults to ``SUDOKU_MODEL_PATH``."""

    app = FastAPI(title="Sudoku Vision", version="0.1.0")
    origins = allow_origins or _default_origins()
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    resolved_model = Path(model_path) if model_path else _model_path_from_env()

    @app.get("/health")
    def health() -> dict[str, Any]:
        return {
            "status": "ok",
            "service": "sudoku-vision",
            "model_loaded": resolved_model.is_file() if resolved_model else False,
        }

    @app.post("/solve")
    def solve(request: SolveRequest) -> dict[str, Any]:
        _validate_grid_shape(request.grid)
        return solve_grid(request.grid)

    @app.post("/recognize")
    async def recognize(
        image: UploadFile = File(...),
        corners: str | None = Form(None),
        board_size: int = Form(900),
    ) -> dict[str, Any]:
        if resolved_model is None or not resolved_model.is_file():
            raise HTTPException(
                status_code=503,
                detail=(
                    "No model available. Set SUDOKU_MODEL_PATH or pass model_path "
                    "to build_app to enable /recognize."
                ),
            )

        try:
            import cv2  # type: ignore
        except ModuleNotFoundError as exc:
            raise HTTPException(
                status_code=503,
                detail="opencv-python not installed in this environment",
            ) from exc

        raw = await image.read()
        buffer = np.frombuffer(raw, dtype=np.uint8)
        decoded = cv2.imdecode(buffer, cv2.IMREAD_COLOR)
        if decoded is None:
            raise HTTPException(status_code=400, detail="Could not decode uploaded image")

        parsed_corners = _parse_corners(corners) if corners else None

        recognizer = _get_recognizer(resolved_model)
        try:
            return recognize_image_array(
                decoded,
                recognizer=recognizer,
                corners=parsed_corners,
                board_size=board_size,
            )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    return app


def _default_origins() -> list[str]:
    raw = os.environ.get("SUDOKU_API_ALLOW_ORIGINS", "")
    if raw:
        return [origin.strip() for origin in raw.split(",") if origin.strip()]
    return [
        "http://localhost",
        "http://localhost:8080",
        "http://127.0.0.1",
        "http://127.0.0.1:8080",
        "app://sudoku-vision",
    ]


def _model_path_from_env() -> Path | None:
    raw = os.environ.get("SUDOKU_MODEL_PATH")
    if not raw:
        return None
    return Path(raw)


_RECOGNIZER_CACHE: dict[str, DigitRecognizer] = {}


def _get_recognizer(model_path: Path) -> DigitRecognizer:
    key = str(model_path.resolve())
    if key not in _RECOGNIZER_CACHE:
        _RECOGNIZER_CACHE[key] = DigitRecognizer(model_path=str(model_path))
    return _RECOGNIZER_CACHE[key]


def _parse_corners(payload: str) -> np.ndarray:
    try:
        data = json.loads(payload)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=422, detail=f"corners must be JSON: {exc}") from exc
    arr = np.asarray(data, dtype=np.float32)
    if arr.shape != (4, 2):
        raise HTTPException(status_code=422, detail="corners must be a 4x2 array")
    return arr


# Convenience for `uvicorn sudoku_vision.api:app`.
app = build_app()
