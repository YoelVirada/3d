import json
import tempfile
from pathlib import Path

from spatial_asset_compiler.capture.mode import detect_capture_mode


def test_detect_arkit_from_poses():
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        (d / "ar" / "frames").mkdir(parents=True)
        (d / "ar" / "poses.json").write_text("[]")
        assert detect_capture_mode(d) == "arkit"


def test_detect_video():
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        (d / "video.mov").write_bytes(b"x")
        assert detect_capture_mode(d) == "video"


def test_detect_from_capture_json():
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        (d / "capture.json").write_text(json.dumps({"capture_mode": "arkit"}))
        (d / "ar" / "frames").mkdir(parents=True)
        (d / "ar" / "poses.json").write_text("[]")
        assert detect_capture_mode(d) == "arkit"
