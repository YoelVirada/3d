"""Capture package schemas and mode detection."""

from spatial_asset_compiler.capture.mode import detect_capture_mode
from spatial_asset_compiler.capture.schema import (
    ARFramePose,
    ARManifest,
    CapturePackage,
    CaptureMode,
)

__all__ = [
    "ARFramePose",
    "ARManifest",
    "CaptureMode",
    "CapturePackage",
    "detect_capture_mode",
]
