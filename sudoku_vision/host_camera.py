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
    from fastapi.responses import HTMLResponse, Response, StreamingResponse
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

    @app.get("/", response_class=HTMLResponse)
    def index() -> str:
        return _viewer_html(source=str(source))

    @app.get("/info")
    def info() -> dict[str, Any]:
        return {
            "service": "sudoku-vision-camera-bridge",
            "source": str(source),
            "endpoints": {
                "GET /": "HTML viewer (live MJPEG)",
                "GET /info": "This JSON",
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


def _viewer_html(source: str) -> str:
    """Tiny standalone viewer page. No external deps; uses MJPEG <img>."""

    safe_source = source.replace("<", "&lt;").replace(">", "&gt;")
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>sudoku-vision camera bridge ({safe_source})</title>
  <style>
    :root {{ color-scheme: light dark; }}
    body {{
      margin: 0;
      font: 14px -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
      background: #111;
      color: #f2f2f7;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 24px 16px 32px;
      gap: 16px;
    }}
    h1 {{
      margin: 0;
      font-size: 17px;
      font-weight: 600;
      letter-spacing: 0.01em;
    }}
    .pill {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 4px 10px;
      border-radius: 999px;
      background: rgba(255,255,255,0.08);
      font-size: 12px;
    }}
    .pill .dot {{
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #30d158;
      box-shadow: 0 0 6px rgba(48,209,88,0.6);
    }}
    .frame {{
      position: relative;
      width: min(960px, 100%);
      aspect-ratio: 16 / 9;
      background: #000;
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 6px 28px rgba(0,0,0,0.5);
    }}
    .frame img {{
      width: 100%;
      height: 100%;
      object-fit: contain;
      display: block;
    }}
    .meta {{
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      font-size: 12px;
      color: #a1a1a6;
    }}
    .meta code {{
      background: rgba(255,255,255,0.06);
      padding: 2px 6px;
      border-radius: 6px;
    }}
    a {{ color: #0a84ff; text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
  </style>
</head>
<body>
  <h1>sudoku-vision camera bridge</h1>
  <span class="pill"><span class="dot"></span>source: <code>{safe_source}</code> · <span id="fc">0</span> frames</span>
  <div class="frame">
    <img src="/stream" alt="live MJPEG stream">
  </div>
  <div class="meta">
    <code>/stream</code>
    <code>/frame.jpg</code>
    <code>/health</code>
    <code>/info</code>
    <span>Container env: <code>SUDOKU_STREAM_URL=http://host.docker.internal:8765/stream</code></span>
  </div>
  <script>
    async function poll() {{
      try {{
        const res = await fetch('/health', {{ cache: 'no-store' }});
        if (res.ok) {{
          const data = await res.json();
          const el = document.getElementById('fc');
          if (el) el.textContent = data.frames_emitted;
        }}
      }} catch (_e) {{}}
      setTimeout(poll, 1000);
    }}
    poll();
  </script>
</body>
</html>
"""


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
