"""Pydantic models for AR and video capture packages."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field

CaptureMode = Literal["arkit", "video"]


class CapturePackage(BaseModel):
    capture_mode: CaptureMode = "video"
    capture_version: str = "1.0"
    device_model: str | None = None
    app_version: str | None = None
    sample_hz: float | None = None
    extra: dict[str, Any] = Field(default_factory=dict)


class ARManifest(BaseModel):
    ar_frame_count: int = 0
    rejected_count: int = 0
    sample_hz: float | None = None
    duration_s: float | None = None


class ARFramePose(BaseModel):
    frame: str
    timestamp_s: float
    tracking_state: str = "normal"
    transform: list[list[float]]
    intrinsics: list[list[float]]
    width: int
    height: int
