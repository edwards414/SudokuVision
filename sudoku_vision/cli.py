"""Command line entrypoints for container health checks and operations."""

from __future__ import annotations

import argparse
import json
import sys
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from typing import Any, Sequence

from sudoku_vision.camera import discover_cameras
from sudoku_vision.pipeline import recognize_image_array, recognize_image_file, solve_grid
from sudoku_vision.recognizer import DigitRecognizer
from sudoku_vision.stream import capture_single_frame


def _package_version() -> str:
    try:
        return version("sudoku-vision")
    except PackageNotFoundError:
        return "0.0.0+local"


def health() -> int:
    payload = {
        "status": "ok",
        "service": "sudoku-vision",
        "version": _package_version(),
    }
    print(json.dumps(payload, separators=(",", ":")))
    return 0


def cameras(args: argparse.Namespace) -> int:
    result = discover_cameras(
        platform_name=args.platform,
        linux_dev_dir=Path(args.dev_dir),
        linux_sysfs_dir=Path(args.sysfs_dir),
        max_indices=args.max_indices,
        require_cv2_probe=args.probe_opencv,
    )
    print(json.dumps(result.to_dict(), separators=(",", ":")))
    return 0


def _load_grid(source: str) -> list[list[int]]:
    if source == "-":
        text = sys.stdin.read()
    else:
        text = Path(source).read_text(encoding="utf-8")
    data = json.loads(text)
    if not isinstance(data, list):
        raise SystemExit("Grid JSON must be a 9x9 array of integers")
    return data


def solve_cmd(args: argparse.Namespace) -> int:
    grid = _load_grid(args.grid)
    payload = solve_grid(grid)
    print(json.dumps(payload, ensure_ascii=False, indent=None if args.compact else 2))
    return 0


def recognize_cmd(args: argparse.Namespace) -> int:
    corners = None
    if args.corners:
        corners_data = json.loads(Path(args.corners).read_text(encoding="utf-8"))
        corners = _parse_corners(corners_data)
    payload: dict[str, Any] = recognize_image_file(
        Path(args.image),
        model_path=Path(args.model),
        corners=corners,
        board_size=args.board_size,
    )
    serialized = json.dumps(payload, ensure_ascii=False, indent=None if args.compact else 2)
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(serialized, encoding="utf-8")
    else:
        print(serialized)
    return 0


def _parse_corners(data: Any):
    import numpy as np  # local import to keep CLI light when unused

    arr = np.asarray(data, dtype=np.float32)
    if arr.shape != (4, 2):
        raise SystemExit("Corners JSON must be a 4x2 array of [x, y] points")
    return arr


def stream_cmd(args: argparse.Namespace) -> int:
    """Grab a single frame from an RTSP/MJPEG/file source and optionally recognise it."""

    corners = None
    if args.corners:
        corners_data = json.loads(Path(args.corners).read_text(encoding="utf-8"))
        corners = _parse_corners(corners_data)

    with capture_single_frame(
        args.source,
        backend=args.backend,
        open_timeout_ms=args.open_timeout_ms,
        read_timeout_ms=args.read_timeout_ms,
    ) as frame:
        if args.save_frame:
            import cv2  # type: ignore

            Path(args.save_frame).parent.mkdir(parents=True, exist_ok=True)
            if not cv2.imwrite(args.save_frame, frame):
                raise SystemExit(f"Could not write frame to {args.save_frame}")

        if args.model:
            recognizer = DigitRecognizer(model_path=args.model)
            payload = recognize_image_array(
                frame,
                recognizer=recognizer,
                corners=corners,
                board_size=args.board_size,
            )
        else:
            payload = {
                "status": "captured",
                "source": args.source,
                "frame_shape": list(frame.shape),
            }

    serialized = json.dumps(payload, ensure_ascii=False, indent=None if args.compact else 2)
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(serialized, encoding="utf-8")
    else:
        print(serialized)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="sudoku-vision")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("health", help="Print container health JSON")

    camera_parser = subparsers.add_parser("cameras", help="List available cameras as JSON")
    camera_parser.add_argument("--platform", help="Override platform detection for testing")
    camera_parser.add_argument("--dev-dir", default="/dev", help="Linux video device directory")
    camera_parser.add_argument(
        "--sysfs-dir",
        default="/sys/class/video4linux",
        help="Linux video4linux sysfs directory",
    )
    camera_parser.add_argument("--max-indices", type=int, default=10, help="Max OpenCV indices to probe")
    camera_parser.add_argument(
        "--probe-opencv",
        action="store_true",
        help="Probe OpenCV indices when platform/device discovery is insufficient",
    )

    solve_parser = subparsers.add_parser("solve", help="Validate and solve a 9x9 grid")
    solve_parser.add_argument(
        "--grid",
        required=True,
        help="Path to a JSON file with a 9x9 array, or '-' to read from stdin",
    )
    solve_parser.add_argument("--compact", action="store_true", help="Emit single-line JSON")

    recognize_parser = subparsers.add_parser(
        "recognize", help="Run the image → grid → solve pipeline"
    )
    recognize_parser.add_argument("--image", required=True, help="Path to a sudoku image")
    recognize_parser.add_argument("--model", required=True, help="Path to the TFLite model")
    recognize_parser.add_argument("--output", help="Write JSON result to this path")
    recognize_parser.add_argument(
        "--corners",
        help="Optional JSON file with manual 4-corner [[x, y], ...] override",
    )
    recognize_parser.add_argument("--board-size", type=int, default=900)
    recognize_parser.add_argument("--compact", action="store_true", help="Emit single-line JSON")

    stream_parser = subparsers.add_parser(
        "stream", help="Grab one frame from an RTSP/MJPEG/HTTP/file source"
    )
    stream_parser.add_argument(
        "source", help="Stream URL or path (e.g. rtsp://..., http://.../mjpeg, /dev/video0)"
    )
    stream_parser.add_argument(
        "--backend",
        help="Capture backend: ffmpeg/rtsp/mjpeg/v4l2/dshow/any (default: auto)",
    )
    stream_parser.add_argument("--open-timeout-ms", type=int, default=5000)
    stream_parser.add_argument("--read-timeout-ms", type=int, default=5000)
    stream_parser.add_argument("--save-frame", help="Optional path to write the captured frame")
    stream_parser.add_argument("--model", help="If set, recognise the captured frame")
    stream_parser.add_argument("--corners", help="Optional manual corners JSON file")
    stream_parser.add_argument("--board-size", type=int, default=900)
    stream_parser.add_argument("--output", help="Write JSON to this path")
    stream_parser.add_argument("--compact", action="store_true")

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "health":
        return health()
    if args.command == "cameras":
        return cameras(args)
    if args.command == "solve":
        return solve_cmd(args)
    if args.command == "recognize":
        return recognize_cmd(args)
    if args.command == "stream":
        return stream_cmd(args)
    parser.error(f"Unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
