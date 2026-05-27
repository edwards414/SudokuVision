"""Host-side camera bridge.

Docker Desktop on macOS / Windows cannot share USB cameras with Linux
containers. This module captures from the host's camera with OpenCV and
exposes the latest frame as

  * ``GET /frame.jpg`` — a single JPEG snapshot (`image/jpeg`)
  * ``GET /stream`` — MJPEG multipart stream (`multipart/x-mixed-replace`)
  * ``GET /health`` — liveness + frames emitted so far

The container then points ``SUDOKU_STREAM_URL`` at
``http://host.docker.internal:<port>/stream`` (or ``/frame.jpg`` for a
single-shot grab).
"""

from __future__ import annotations

import argparse
import threading
import time
from contextlib import asynccontextmanager
from typing import Any, Iterator

try:
    from fastapi import FastAPI, HTTPException
    from fastapi.responses import Response, StreamingResponse
except ModuleNotFoundError as exc:  # pragma: no cover - import-time guard
    raise RuntimeError(
        "FastAPI is required for the host camera bridge. "
        "Install with `pip install -e .[api]`."
    ) from exc

from sudoku_vision.errors import OptionalDependencyError


def _require_cv2():
    try:
        import cv2  # type: ignore
    except ModuleNotFoundError as exc:  # pragma: no cover - guard
        raise OptionalDependencyError("opencv-python", "host camera bridge") from exc
    return cv2


class CameraBridge:
    """Reads frames from ``source`` in a background thread and keeps the
    latest JPEG-encoded payload in memory."""

    def __init__(
        self,
        source: int | str,
        *,
        fps_cap: float = 30.0,
        warmup_frames: int = 10,
        jpeg_quality: int = 80,
    ) -> None:
        self.source = source
        self.fps_cap = max(1.0, fps_cap)
        self.warmup_frames = max(0, warmup_frames)
        self.jpeg_quality = max(1, min(100, jpeg_quality))
        self._latest: bytes | None = None
        self._frame_no = 0
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._open_failed: str | None = None

    def start(self) -> None:
        if self._thread is not None:
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, name="camera-bridge", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=2.0)
            self._thread = None

    def latest(self) -> tuple[bytes | None, int]:
        with self._lock:
            return self._latest, self._frame_no

    def open_error(self) -> str | None:
        return self._open_failed

    def _run(self) -> None:  # pragma: no cover - exercised via tests with fake cv2
        cv2 = _require_cv2()
        capture = cv2.VideoCapture(self.source)
        if not capture.isOpened():
            capture.release()
            self._open_failed = f"could not open source {self.source!r}"
            return
        for _ in range(self.warmup_frames):
            capture.read()
        min_dt = 1.0 / self.fps_cap
        try:
            while not self._stop.is_set():
                ok, frame = capture.read()
                if not ok or frame is None:
                    time.sleep(0.05)
                    continue
                ok, buf = cv2.imencode(
                    ".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), self.jpeg_quality]
                )
                if not ok:
                    continue
                with self._lock:
                    self._latest = buf.tobytes()
                    self._frame_no += 1
                # Sleep just under the target interval; cap.read blocks for ~1/fps anyway.
                time.sleep(max(0.0, min_dt - 0.005))
        finally:
            capture.release()


def build_bridge_app(
    source: int | str,
    *,
    fps_cap: float = 30.0,
    warmup_frames: int = 10,
    jpeg_quality: int = 80,
) -> FastAPI:
    bridge = CameraBridge(
        source,
        fps_cap=fps_cap,
        warmup_frames=warmup_frames,
        jpeg_quality=jpeg_quality,
    )

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        bridge.start()
        try:
            yield
        finally:
            bridge.stop()

    app = FastAPI(
        title="sudoku-vision host camera bridge",
        version="0.1.0",
        lifespan=lifespan,
    )

    @app.get("/")
    def index() -> dict[str, Any]:
        return {
            "service": "sudoku-vision-camera-bridge",
            "source": str(source),
            "endpoints": {
                "GET /health": "Liveness + frames_emitted",
                "GET /frame.jpg": "Latest captured frame as JPEG",
                "GET /stream": "MJPEG multipart stream",
            },
            "container_hint": (
                "Set SUDOKU_STREAM_URL=http://host.docker.internal:<port>/stream"
                " (or /frame.jpg) inside the sudoku-vision container."
            ),
        }

    @app.get("/health")
    def health() -> dict[str, Any]:
        _, frame_no = bridge.latest()
        return {
            "status": "ok",
            "source": str(source),
            "frames_emitted": frame_no,
            "open_error": bridge.open_error(),
        }

    @app.get("/frame.jpg")
    def frame() -> Response:
        data, _ = bridge.latest()
        if data is None:
            err = bridge.open_error()
            if err:
                raise HTTPException(status_code=503, detail=err)
            raise HTTPException(status_code=503, detail="no frame captured yet")
        return Response(content=data, media_type="image/jpeg")

    @app.get("/stream")
    def stream() -> StreamingResponse:
        return StreamingResponse(
            _mjpeg_iter(bridge, fps_cap=fps_cap),
            media_type="multipart/x-mixed-replace; boundary=frame",
        )

    app.state.bridge = bridge
    return app


def _mjpeg_iter(bridge: CameraBridge, *, fps_cap: float) -> Iterator[bytes]:
    boundary = b"--frame\r\n"
    period = 1.0 / max(1.0, fps_cap)
    last_no = -1
    while True:
        data, frame_no = bridge.latest()
        if data is None:
            time.sleep(0.05)
            continue
        if frame_no == last_no:
            time.sleep(period / 2)
            continue
        last_no = frame_no
        yield (
            boundary
            + b"Content-Type: image/jpeg\r\n"
            + f"Content-Length: {len(data)}\r\n\r\n".encode("ascii")
            + data
            + b"\r\n"
        )
        time.sleep(period)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="sudoku-vision-camera-bridge")
    parser.add_argument(
        "--source",
        default="0",
        help="Camera index (0, 1, ...) or any cv2 URL (rtsp://..., http://...).",
    )
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--warmup", type=int, default=10)
    parser.add_argument("--jpeg-quality", type=int, default=80)
    args = parser.parse_args(argv)

    source: int | str = args.source
    if isinstance(source, str) and source.lstrip("-").isdigit():
        source = int(source)

    app = build_bridge_app(
        source,
        fps_cap=args.fps,
        warmup_frames=args.warmup,
        jpeg_quality=args.jpeg_quality,
    )

    try:
        import uvicorn  # type: ignore
    except ModuleNotFoundError as exc:  # pragma: no cover - install hint only
        raise RuntimeError(
            "uvicorn missing. Install with `pip install -e .[api]`."
        ) from exc

    print(f"Camera bridge: http://{args.host}:{args.port}/  (source={source})")
    print(f"  /stream     MJPEG multipart")
    print(f"  /frame.jpg  Latest JPEG snapshot")
    print(f"  /health     Liveness")
    print(
        "Container env:"
        f" SUDOKU_STREAM_URL=http://host.docker.internal:{args.port}/stream"
    )

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
