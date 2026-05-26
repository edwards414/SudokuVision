import json
import subprocess
import sys

from sudoku_vision.camera import discover_cameras


class FakeCapture:
    def __init__(self, opened):
        self._opened = opened
        self.released = False

    def isOpened(self):
        return self._opened

    def release(self):
        self.released = True

    def get(self, prop_id):
        return {3: 1280.0, 4: 720.0}.get(prop_id, 0.0)


class FakeCv2:
    CAP_DSHOW = 700
    CAP_PROP_FRAME_WIDTH = 3
    CAP_PROP_FRAME_HEIGHT = 4

    def __init__(self, opened_indices):
        self.opened_indices = set(opened_indices)
        self.calls = []

    def VideoCapture(self, index, backend=None):
        self.calls.append((index, backend))
        return FakeCapture(index in self.opened_indices)


def test_linux_discovery_reads_dev_video_devices_and_sysfs_names(tmp_path):
    dev_dir = tmp_path / "dev"
    sysfs_dir = tmp_path / "sys" / "class" / "video4linux"
    dev_dir.mkdir()
    (dev_dir / "video0").touch()
    (dev_dir / "video2").touch()
    (sysfs_dir / "video0").mkdir(parents=True)
    (sysfs_dir / "video2").mkdir(parents=True)
    (sysfs_dir / "video0" / "name").write_text("USB Camera\n", encoding="utf-8")
    (sysfs_dir / "video2" / "name").write_text("HDMI Capture\n", encoding="utf-8")

    result = discover_cameras(
        platform_name="Linux",
        linux_dev_dir=dev_dir,
        linux_sysfs_dir=sysfs_dir,
    )

    assert result.platform == "Linux"
    assert [device.id for device in result.devices] == ["linux:/dev/video0", "linux:/dev/video2"]
    assert [device.name for device in result.devices] == ["USB Camera", "HDMI Capture"]
    assert [device.index for device in result.devices] == [0, 2]


def test_windows_discovery_probes_opencv_indices_with_directshow():
    fake_cv2 = FakeCv2(opened_indices={0, 3})

    result = discover_cameras(
        platform_name="Windows",
        cv2_module=fake_cv2,
        max_indices=5,
    )

    assert [device.id for device in result.devices] == ["opencv:0", "opencv:3"]
    assert [device.backend for device in result.devices] == ["opencv-dshow", "opencv-dshow"]
    assert result.devices[0].width == 1280
    assert result.devices[0].height == 720
    assert fake_cv2.calls[0] == (0, fake_cv2.CAP_DSHOW)


def test_windows_discovery_without_opencv_returns_warning():
    result = discover_cameras(
        platform_name="Windows",
        cv2_module=None,
        require_cv2_probe=True,
    )

    assert result.devices == []
    assert result.warnings == ["OpenCV is required to probe cameras on Windows"]


def test_cli_cameras_outputs_json_for_linux_dev_dir(tmp_path):
    dev_dir = tmp_path / "dev"
    sysfs_dir = tmp_path / "sys" / "class" / "video4linux"
    dev_dir.mkdir()
    (dev_dir / "video1").touch()
    (sysfs_dir / "video1").mkdir(parents=True)
    (sysfs_dir / "video1" / "name").write_text("Document Camera\n", encoding="utf-8")

    completed = subprocess.run(
        [
            sys.executable,
            "-m",
            "sudoku_vision.cli",
            "cameras",
            "--platform",
            "Linux",
            "--dev-dir",
            str(dev_dir),
            "--sysfs-dir",
            str(sysfs_dir),
        ],
        check=True,
        capture_output=True,
        text=True,
    )

    payload = json.loads(completed.stdout)
    assert payload["platform"] == "Linux"
    assert payload["devices"][0]["id"] == "linux:/dev/video1"
    assert payload["devices"][0]["name"] == "Document Camera"
