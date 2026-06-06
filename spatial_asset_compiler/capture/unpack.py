"""Unpack and validate AR capture zip packages."""

from __future__ import annotations

import json
import zipfile
from pathlib import Path


def validate_arkit_layout(capture_dir: Path) -> None:
    poses = capture_dir / "ar" / "poses.json"
    frames = capture_dir / "ar" / "frames"
    if not poses.exists():
        raise ValueError(f"Missing {poses}")
    if not frames.is_dir():
        raise ValueError(f"Missing {frames}")
    raw = json.loads(poses.read_text(encoding="utf-8"))
    if not isinstance(raw, list) or not raw:
        raise ValueError("ar/poses.json must be a non-empty array")
    for entry in raw:
        frame_name = entry.get("frame")
        if not frame_name or not (frames / frame_name).exists():
            raise ValueError(f"Pose references missing frame: {frame_name}")


def unpack_ar_capture_zip(zip_path: Path, dest: Path) -> Path:
    dest.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(dest)
    validate_arkit_layout(dest)
    cap_json = dest / "capture.json"
    meta: dict = {}
    if cap_json.exists():
        meta = json.loads(cap_json.read_text(encoding="utf-8"))
    meta["capture_mode"] = "arkit"
    meta.setdefault("capture_version", "1.0")
    cap_json.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return dest


def save_video_capture(
    dest: Path,
    video_content: bytes,
    filename: str,
    metadata: str,
) -> tuple[Path, Path, int]:
    dest.mkdir(parents=True, exist_ok=True)
    ext = Path(filename or "video.mp4").suffix or ".mp4"
    video_path = dest / f"video{ext}"
    video_path.write_bytes(video_content)
    try:
        meta = json.loads(metadata)
    except json.JSONDecodeError:
        meta = {"raw": metadata}
    meta["capture_mode"] = "video"
    cap_json = dest / "capture.json"
    cap_json.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return video_path, cap_json, len(video_content)
