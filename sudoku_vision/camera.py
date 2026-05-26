"""Cross-platform camera discovery helpers."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
import platform
import re
from typing import Any


_AUTO_CV2 = object()


@dataclass(frozen=True)
class CameraDevice:
    """A camera source that can be shown to UI/API clients."""

    id: str
    name: str
    platform: str
    backend: str
    index: int | None = None
    path: str | None = None
    width: int | None = None
    height: int | None = None

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


@dataclass(frozen=True)
class CameraDiscoveryResult:
    platform: str
    devices: list[CameraDevice]
    warnings: list[str]

    def to_dict(self) -> dict[str, object]:
        return {
            "platform": self.platform,
            "devices": [device.to_dict() for device in self.devices],
            "warnings": self.warnings,
        }


def _canonical_platform(platform_name: str | None) -> str:
    name = platform_name or platform.system()
    lowered = name.lower()
    if lowered.startswith("linux"):
        return "Linux"
    if lowered.startswith("win"):
        return "Windows"
    if lowered.startswith("darwin") or lowered.startswith("mac"):
        return "Darwin"
    return name


def _video_index(path: Path) -> int | None:
    match = re.fullmatch(r"video(\d+)", path.name)
    if match is None:
        return None
    return int(match.group(1))


def _read_linux_camera_name(sysfs_dir: Path, dev_name: str, fallback: str) -> str:
    name_file = sysfs_dir / dev_name / "name"
    try:
        name = name_file.read_text(encoding="utf-8").strip()
    except OSError:
        return fallback
    return name or fallback


def _discover_linux_cameras(dev_dir: Path, sysfs_dir: Path) -> list[CameraDevice]:
    devices: list[CameraDevice] = []
    for path in sorted(dev_dir.glob("video*"), key=lambda item: (_video_index(item) is None, item.name)):
        index = _video_index(path)
        if index is None:
            continue
        dev_name = f"video{index}"
        name = _read_linux_camera_name(sysfs_dir, dev_name, fallback=f"Video Device {index}")
        devices.append(
            CameraDevice(
                id=f"linux:/dev/{dev_name}",
                name=name,
                platform="Linux",
                backend="v4l2",
                index=index,
                path=str(path),
            )
        )
    return devices


def _load_cv2(cv2_module: Any, platform_name: str) -> tuple[Any | None, str | None]:
    warning = (
        "OpenCV is required to probe cameras on Windows"
        if platform_name == "Windows"
        else "OpenCV is required to probe cameras on this platform"
    )
    if cv2_module is not _AUTO_CV2:
        if cv2_module is None:
            return None, warning
        return cv2_module, None

    try:
        import cv2  # type: ignore
    except ModuleNotFoundError:
        return None, warning
    return cv2, None


def _capture_dimension(capture: Any, prop_id: int | None) -> int | None:
    if prop_id is None:
        return None
    try:
        value = int(capture.get(prop_id))
    except (AttributeError, TypeError, ValueError):
        return None
    return value if value > 0 else None


def _probe_opencv_cameras(
    *,
    cv2_module: Any,
    platform_name: str,
    max_indices: int,
) -> list[CameraDevice]:
    devices: list[CameraDevice] = []
    use_directshow = platform_name == "Windows" and hasattr(cv2_module, "CAP_DSHOW")
    backend = "opencv-dshow" if use_directshow else "opencv"
    width_prop = getattr(cv2_module, "CAP_PROP_FRAME_WIDTH", None)
    height_prop = getattr(cv2_module, "CAP_PROP_FRAME_HEIGHT", None)

    for index in range(max_indices):
        capture = (
            cv2_module.VideoCapture(index, cv2_module.CAP_DSHOW)
            if use_directshow
            else cv2_module.VideoCapture(index)
        )
        try:
            if not capture.isOpened():
                continue
            devices.append(
                CameraDevice(
                    id=f"opencv:{index}",
                    name=f"Camera {index}",
                    platform=platform_name,
                    backend=backend,
                    index=index,
                    width=_capture_dimension(capture, width_prop),
                    height=_capture_dimension(capture, height_prop),
                )
            )
        finally:
            capture.release()

    return devices


def discover_cameras(
    *,
    platform_name: str | None = None,
    linux_dev_dir: str | Path = Path("/dev"),
    linux_sysfs_dir: str | Path = Path("/sys/class/video4linux"),
    cv2_module: Any = _AUTO_CV2,
    max_indices: int = 10,
    require_cv2_probe: bool = False,
) -> CameraDiscoveryResult:
    """Discover local camera devices on Linux and Windows.

    Linux discovery reads `/dev/video*` and sysfs metadata, which also works
    inside Docker when video devices are mounted into the container. Windows
    discovery probes numeric OpenCV camera indices with DirectShow.
    """

    if max_indices < 0:
        raise ValueError("max_indices must be non-negative")

    system = _canonical_platform(platform_name)
    warnings: list[str] = []

    if system == "Linux":
        devices = _discover_linux_cameras(Path(linux_dev_dir), Path(linux_sysfs_dir))
        if devices or not require_cv2_probe:
            return CameraDiscoveryResult(platform=system, devices=devices, warnings=warnings)

    cv2, warning = _load_cv2(cv2_module, system)
    if cv2 is None:
        if warning:
            warnings.append(warning)
        return CameraDiscoveryResult(platform=system, devices=[], warnings=warnings)

    devices = _probe_opencv_cameras(
        cv2_module=cv2,
        platform_name=system,
        max_indices=max_indices,
    )
    return CameraDiscoveryResult(platform=system, devices=devices, warnings=warnings)
