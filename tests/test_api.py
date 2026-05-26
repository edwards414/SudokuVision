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
