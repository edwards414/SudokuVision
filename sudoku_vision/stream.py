"""RTSP / MJPEG / file-backed frame readers used by the recognise pipeline."""

from __future__ import annotations

from contextlib import contextmanager
from typing import Iterator

import numpy as np

from sudoku_vision.errors import OptionalDependencyError


class FrameReadError(Exception):
    """Raised when the upstream stream cannot deliver a frame."""

    def __init__(self, *, source: str, reason: str) -> None:
        super().__init__(f"FrameReadError({source!r}): {reason}")
        self.source = source
        self.reason = reason


class FrameReader:
    """Thin wrapper around ``cv2.VideoCapture`` for RTSP/MJPEG/HTTP streams.

    The reader does not run a background thread; ``read_frame`` blocks the
    caller for one ``VideoCapture.read`` call. Use ``capture_single_frame`` for
    a one-shot grab that opens, reads, and closes the capture in one go — that
    is the path the CLI/API expose.
    """

    def __init__(
        self,
        source: str,
        *,
        backend: str | int | None = None,
        open_timeout_ms: int = 5000,
        read_timeout_ms: int = 5000,
    ) -> None:
        self.source = source
        self._backend = backend
        self._open_timeout_ms = open_timeout_ms
        self._read_timeout_ms = read_timeout_ms
        self._capture = None  # type: ignore[var-annotated]

    def open(self) -> None:
        cv2 = _require_cv2()
        backend = _resolve_backend(cv2, self._backend)
        if backend is None:
            capture = cv2.VideoCapture(self.source)
        else:
            capture = cv2.VideoCapture(self.source, backend)
        # CAP_PROP_OPEN_TIMEOUT_MSEC / CAP_PROP_READ_TIMEOUT_MSEC are honored by
        # the FFmpeg backend used for RTSP/HTTP streams; setting them on other
        # backends is a no-op.
        try:
            capture.set(cv2.CAP_PROP_OPEN_TIMEOUT_MSEC, self._open_timeout_ms)
            capture.set(cv2.CAP_PROP_READ_TIMEOUT_MSEC, self._read_timeout_ms)
        except AttributeError:  # pragma: no cover - older opencv builds
            pass
        if not capture.isOpened():
            capture.release()
            raise FrameReadError(source=self.source, reason="could not open stream")
        self._capture = capture

    def read_frame(self) -> np.ndarray:
        if self._capture is None:
            raise FrameReadError(source=self.source, reason="reader is not open")
        ok, frame = self._capture.read()
        if not ok or frame is None:
            raise FrameReadError(source=self.source, reason="empty frame from stream")
        return frame

    def close(self) -> None:
        if self._capture is not None:
            try:
                self._capture.release()
            finally:
                self._capture = None

    def __enter__(self) -> "FrameReader":
        self.open()
        return self

    def __exit__(self, *_exc) -> None:
        self.close()


def _require_cv2():
    try:
        import cv2  # type: ignore
    except ModuleNotFoundError as exc:  # pragma: no cover - guard
        raise OptionalDependencyError("opencv-python", "camera streaming") from exc
    return cv2


def _resolve_backend(cv2, requested: str | int | None):
    if requested is None:
        return None
    if isinstance(requested, int):
        return requested
    name = requested.lower()
    aliases = {
        "ffmpeg": "CAP_FFMPEG",
        "rtsp": "CAP_FFMPEG",
        "mjpeg": "CAP_FFMPEG",
        "any": "CAP_ANY",
        "gstreamer": "CAP_GSTREAMER",
        "v4l2": "CAP_V4L2",
        "dshow": "CAP_DSHOW",
    }
    attr = aliases.get(name, requested.upper())
    return getattr(cv2, attr, None)


@contextmanager
def capture_single_frame(
    source: str,
    *,
    backend: str | int | None = None,
    open_timeout_ms: int = 5000,
    read_timeout_ms: int = 5000,
) -> Iterator[np.ndarray]:
    """Context manager that opens ``source``, reads one frame, and tears down.

    The frame is yielded as a BGR numpy array (``ndim == 3``). The capture is
    always released, even if ``read_frame`` raises.
    """

    reader = FrameReader(
        source,
        backend=backend,
        open_timeout_ms=open_timeout_ms,
        read_timeout_ms=read_timeout_ms,
    )
    reader.open()
    try:
        yield reader.read_frame()
    finally:
        reader.close()
