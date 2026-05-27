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
from sudoku_vision.stream import capture_single_frame


class SolveRequest(BaseModel):
    grid: list[list[int]] = Field(
        ...,
        description="9x9 array of integers, 0 = empty, 1-9 = given.",
        min_length=9,
        max_length=9,
    )


class CaptureRequest(BaseModel):
    corners: list[list[float]] | None = Field(
        default=None,
        description="Optional 4x2 manual corner override in pixel space.",
    )
    board_size: int = Field(default=900, ge=180, le=4000)
    warmup_frames: int = Field(
        default=10,
        ge=0,
        le=120,
        description="Frames to discard after opening before grabbing one.",
    )
    source: str | None = Field(
        default=None,
        description=(
            "Optional one-off override. Numeric strings ('0', '2') are treated"
            " as local camera indices; anything else is passed to cv2 as-is"
            " (rtsp://..., http://..., tcp://..., file path)."
        ),
    )

    model_config = {
        "json_schema_extra": {
            "examples": [
                {"warmup_frames": 10},
                {
                    "warmup_frames": 15,
                    "board_size": 900,
                    "corners": [[120, 80], [820, 80], [820, 780], [120, 780]],
                },
                {"source": "rtsp://user:pass@192.168.1.50:554/stream1"},
            ]
        }
    }


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

    @app.get("/")
    def index() -> dict[str, Any]:
        return {
            "service": "sudoku-vision",
            "version": "0.1.0",
            "docs": "/docs",
            "endpoints": {
                "GET /health": "Liveness + model_loaded flag",
                "POST /solve": "Validate + solve a JSON 9x9 grid",
                "POST /recognize": "Multipart image upload → recognise + solve",
                "POST /recognize/capture": (
                    "Grab a frame from the configured camera / stream"
                    " (SUDOKU_CAMERA_INDEX / SUDOKU_STREAM_URL) → recognise + solve"
                ),
            },
            "configured_source": _describe_source(),
            "model_loaded": resolved_model.is_file() if resolved_model else False,
        }

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

    @app.post("/recognize/capture")
    def recognize_capture(
        request: CaptureRequest = CaptureRequest(),  # noqa: B008
    ) -> dict[str, Any]:
        if resolved_model is None or not resolved_model.is_file():
            raise HTTPException(
                status_code=503,
                detail=(
                    "No model available. Set SUDOKU_MODEL_PATH or pass"
                    " model_path to build_app to enable /recognize/capture."
                ),
            )
        source = request.source or _configured_camera_source()
        if source is None:
            raise HTTPException(
                status_code=503,
                detail=(
                    "No camera or stream configured. Set SUDOKU_CAMERA_INDEX or"
                    " SUDOKU_STREAM_URL, or pass `source` in the request body."
                ),
            )
        parsed_corners = None
        if request.corners is not None:
            arr = np.asarray(request.corners, dtype=np.float32)
            if arr.shape != (4, 2):
                raise HTTPException(status_code=422, detail="corners must be a 4x2 array")
            parsed_corners = arr

        recognizer = _get_recognizer(resolved_model)
        try:
            with capture_single_frame(source, warmup_frames=request.warmup_frames) as frame:
                return recognize_image_array(
                    frame,
                    recognizer=recognizer,
                    corners=parsed_corners,
                    board_size=request.board_size,
                )
        except Exception as exc:  # noqa: BLE001 - surface stream errors verbatim
            raise HTTPException(status_code=502, detail=str(exc)) from exc

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


def _describe_source() -> dict[str, Any]:
    source = _configured_camera_source()
    if source is None:
        return {
            "kind": "none",
            "value": None,
            "hint": "Set SUDOKU_CAMERA_INDEX or SUDOKU_STREAM_URL to enable /recognize/capture.",
        }
    if isinstance(source, int):
        return {"kind": "camera", "index": source}
    return {"kind": "stream", "url": source}


def _configured_camera_source() -> str | int | None:
    """Pick the host-configured camera source.

    Priority: SUDOKU_CAMERA_INDEX (numeric) > SUDOKU_STREAM_URL (any cv2 URL)
    > None. Numeric strings are coerced to int so cv2 picks the camera
    backend instead of treating it as a file path."""

    raw_index = os.environ.get("SUDOKU_CAMERA_INDEX", "").strip()
    if raw_index:
        try:
            return int(raw_index)
        except ValueError:
            # Non-numeric value — fall through to STREAM_URL.
            pass
    url = os.environ.get("SUDOKU_STREAM_URL", "").strip()
    if url:
        return url
    return None


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
