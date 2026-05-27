"""Host-side camera bridge service used to feed a container that cannot
access the host's USB camera directly (Docker Desktop on macOS/Windows)."""

from __future__ import annotations

import time

import numpy as np
import pytest

fastapi = pytest.importorskip("fastapi")
cv2 = pytest.importorskip("cv2")
from fastapi.testclient import TestClient  # noqa: E402

from sudoku_vision.host_camera import CameraBridge, build_bridge_app  # noqa: E402


class _FakeCapture:
    def __init__(self, frames=None) -> None:
        default = [np.full((90, 160, 3), 200, dtype=np.uint8)]
        self._frames = list(default if frames is None else frames)
        self.released = False
        self.calls = 0

    def isOpened(self) -> bool:
        return True

    def read(self):
        self.calls += 1
        if not self._frames:
            return False, None
        # Round-robin so the bridge's loop always has something to emit.
        frame = self._frames[(self.calls - 1) % len(self._frames)]
        return True, frame.copy()

    def release(self) -> None:
        self.released = True

    def set(self, *_args, **_kwargs) -> None:
        pass


def _patch_capture(monkeypatch, fake: _FakeCapture) -> None:
    monkeypatch.setattr(cv2, "VideoCapture", lambda *_a, **_k: fake)


def test_camera_bridge_produces_jpeg_after_start(monkeypatch):
    fake = _FakeCapture()
    _patch_capture(monkeypatch, fake)

    bridge = CameraBridge(source=0, fps_cap=60.0, warmup_frames=0)
    bridge.start()
    try:
        deadline = time.time() + 2.0
        data, frame_no = bridge.latest()
        while data is None and time.time() < deadline:
            time.sleep(0.02)
            data, frame_no = bridge.latest()
        assert data is not None
        assert frame_no >= 1
        # The bytes should be a JPEG (starts with FFD8FF).
        assert data[:3] == b"\xff\xd8\xff"
    finally:
        bridge.stop()
    assert fake.released is True


def test_bridge_app_serves_frame_and_health(monkeypatch):
    fake = _FakeCapture()
    _patch_capture(monkeypatch, fake)

    app = build_bridge_app(source=0, fps_cap=60.0, warmup_frames=0)
    with TestClient(app) as client:
        # Allow the background thread a moment to capture once.
        deadline = time.time() + 2.0
        status = 503
        while status != 200 and time.time() < deadline:
            response = client.get("/frame.jpg")
            status = response.status_code
            if status != 200:
                time.sleep(0.05)
        assert status == 200, response.text
        assert response.headers["content-type"] == "image/jpeg"
        assert response.content[:3] == b"\xff\xd8\xff"

        health = client.get("/health")
        assert health.status_code == 200
        payload = health.json()
        assert payload["status"] == "ok"
        assert payload["source"] == "0"
        assert payload["frames_emitted"] >= 1
