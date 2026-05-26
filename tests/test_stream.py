"""Frame reader contract."""

from __future__ import annotations

import numpy as np
import pytest

from sudoku_vision.stream import (
    FrameReadError,
    FrameReader,
    capture_single_frame,
)


class _FakeCapture:
    """Minimal cv2.VideoCapture stand-in."""

    def __init__(self, opens: bool = True, frames=None) -> None:
        self._opens = opens
        default = [np.zeros((4, 4, 3), dtype=np.uint8)]
        self._frames = list(default if frames is None else frames)
        self.released = False

    def isOpened(self) -> bool:
        return self._opens

    def read(self):
        if not self._frames:
            return False, None
        return True, self._frames.pop(0)

    def release(self) -> None:
        self.released = True

    def set(self, *_args, **_kwargs) -> None:
        pass


def test_frame_reader_raises_when_capture_does_not_open(monkeypatch):
    pytest.importorskip("cv2")
    import cv2  # type: ignore

    fake = _FakeCapture(opens=False)
    monkeypatch.setattr(cv2, "VideoCapture", lambda *a, **k: fake)
    reader = FrameReader("rtsp://fake")
    with pytest.raises(FrameReadError):
        reader.open()
    assert fake.released is True


def test_frame_reader_returns_frame_then_releases(monkeypatch):
    pytest.importorskip("cv2")
    import cv2  # type: ignore

    frame = np.full((8, 8, 3), 200, dtype=np.uint8)
    fake = _FakeCapture(frames=[frame])
    monkeypatch.setattr(cv2, "VideoCapture", lambda *a, **k: fake)

    with capture_single_frame("rtsp://fake") as captured:
        assert captured.shape == (8, 8, 3)
        assert int(captured.mean()) == 200
    assert fake.released is True


def test_frame_reader_raises_on_empty_frame(monkeypatch):
    pytest.importorskip("cv2")
    import cv2  # type: ignore

    fake = _FakeCapture(frames=[])
    monkeypatch.setattr(cv2, "VideoCapture", lambda *a, **k: fake)

    with pytest.raises(FrameReadError):
        with capture_single_frame("rtsp://fake"):
            pass
    assert fake.released is True
