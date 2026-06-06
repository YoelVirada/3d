"""Detect capture mode from on-disk capture package."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Literal

from spatial_asset_compiler.capture.schema import CaptureMode

CaptureModeLiteral = Literal["arkit", "video"]


def detect_capture_mode(capture_dir: Path) -> CaptureModeLiteral:
    if not capture_dir.is_dir():
        raise FileNotFoundError(f"Capture package not found: {capture_dir}")

    cap_json = capture_dir / "capture.json"
    if cap_json.exists():
        try:
            raw = json.loads(cap_json.read_text(encoding="utf-8"))
            mode = raw.get("capture_mode")
            if mode in ("arkit", "video"):
                return mode  # type: ignore[return-value]
        except json.JSONDecodeError:
            pass

    if (capture_dir / "ar" / "poses.json").exists():
        return "arkit"

    if list(capture_dir.glob("video.*")):
        return "video"

    raise FileNotFoundError(
        f"No ARKit package (ar/poses.json) or video.* in {capture_dir}"
    )
