"""Command line entrypoints for container health checks and operations."""

from __future__ import annotations

import argparse
import json
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from typing import Sequence

from sudoku_vision.camera import discover_cameras


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
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "health":
        return health()
    if args.command == "cameras":
        return cameras(args)
    parser.error(f"Unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
