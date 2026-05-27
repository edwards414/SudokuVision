"""HTTP API surface for the Sudoku Vision service."""

from __future__ import annotations

import json
from typing import Any

import pytest

fastapi = pytest.importorskip("fastapi")
from fastapi.testclient import TestClient  # noqa: E402

from sudoku_vision.api import build_app  # noqa: E402

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


@pytest.fixture()
def client() -> TestClient:
    return TestClient(build_app())


def test_health_returns_ok(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["service"] == "sudoku-vision"


def test_solve_returns_solved_for_valid_grid(client: TestClient) -> None:
    response = client.post("/solve", json={"grid": VALID_PUZZLE})
    assert response.status_code == 200, response.text
    payload: dict[str, Any] = response.json()
    assert payload["validation"]["is_valid"] is True
    assert payload["solve"]["status"] == "solved"
    assert payload["solve"]["has_unique_solution"] is True


def test_solve_returns_invalid_puzzle_for_duplicate_row(client: TestClient) -> None:
    bad = [list(row) for row in VALID_PUZZLE]
    bad[0][0] = 7
    response = client.post("/solve", json={"grid": bad})
    assert response.status_code == 200
    payload = response.json()
    assert payload["validation"]["is_valid"] is False
    assert payload["solve"] is None


def test_solve_rejects_non_9x9_grid(client: TestClient) -> None:
    response = client.post("/solve", json={"grid": [[0] * 9 for _ in range(8)]})
    assert response.status_code == 422


def test_recognize_endpoint_accepts_corners_field(client: TestClient) -> None:
    # We don't have an image fixture nor a trained model in CI here, so we just
    # verify the endpoint accepts the documented multipart shape and returns
    # 400/500 (not 422) — the schema is valid even if the worker isn't.
    response = client.post(
        "/recognize",
        files={"image": ("blank.png", b"not-a-real-image", "image/png")},
        data={"corners": json.dumps([[0, 0], [1, 0], [1, 1], [0, 1]])},
    )
    assert response.status_code in {400, 500, 503}


def test_recognize_capture_uses_configured_camera(monkeypatch, tmp_path) -> None:
    import numpy as np
    from sudoku_vision import api as api_module

    captured_sources: list = []

    def fake_capture(source, *, backend=None, open_timeout_ms=5000,
                     read_timeout_ms=5000, warmup_frames=0):
        captured_sources.append((source, warmup_frames))

        class _Ctx:
            def __enter__(self_inner):
                return np.full((180, 180, 3), 200, dtype=np.uint8)

            def __exit__(self_inner, *a):
                return None

        return _Ctx()

    fake_payload = {
        "grid": [[0] * 9 for _ in range(9)],
        "confidence": [[1.0] * 9 for _ in range(9)],
        "low_confidence_cells": [],
        "validation": {"is_valid": True, "issues": []},
        "solve": {
            "status": "multiple_solutions",
            "has_unique_solution": False,
            "solution": [[0] * 9 for _ in range(9)],
            "message": None,
            "issues": [],
        },
        "status": "multiple_solutions",
        "board_corners": [[0, 0], [1, 0], [1, 1], [0, 1]],
    }

    def fake_recognize_image_array(_frame, *, recognizer, corners=None, board_size=900):
        return fake_payload

    def fake_get_recognizer(_path):
        return object()

    monkeypatch.setattr(api_module, "capture_single_frame", fake_capture)
    monkeypatch.setattr(api_module, "recognize_image_array", fake_recognize_image_array)
    monkeypatch.setattr(api_module, "_get_recognizer", fake_get_recognizer)

    fake_model = tmp_path / "model.tflite"
    fake_model.write_bytes(b"stub")
    app = api_module.build_app(model_path=fake_model)
    client = TestClient(app)

    monkeypatch.setenv("SUDOKU_CAMERA_INDEX", "2")
    response = client.post("/recognize/capture", json={"warmup_frames": 7})

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "multiple_solutions"
    assert captured_sources == [(2, 7)]


def test_recognize_capture_returns_503_when_no_source_configured(
    monkeypatch, tmp_path
) -> None:
    from sudoku_vision import api as api_module

    monkeypatch.delenv("SUDOKU_CAMERA_INDEX", raising=False)
    monkeypatch.delenv("SUDOKU_STREAM_URL", raising=False)

    fake_model = tmp_path / "model.tflite"
    fake_model.write_bytes(b"stub")
    app = api_module.build_app(model_path=fake_model)
    client = TestClient(app)

    response = client.post("/recognize/capture", json={})
    assert response.status_code == 503
    assert "camera" in response.text.lower() or "stream" in response.text.lower()


def test_cors_allows_local_flutter_origin(client: TestClient) -> None:
    response = client.options(
        "/health",
        headers={
            "Origin": "http://localhost:8080",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert response.status_code in {200, 204}
    assert response.headers.get("access-control-allow-origin") == "http://localhost:8080"
