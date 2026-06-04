"""Pydantic schemas for spatial asset package files."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class CaptureMetadata(BaseModel):
    device_model: str | None = None
    camera_type: str | None = None
    resolution: str | None = None
    duration_s: float | None = None
    orientation: str | None = None
    timestamp: str | None = None
    fps: float | None = None


class StreamingHints(BaseModel):
    chunk_strategy: str = "per_object"
    lod_supported: bool = False
    preview_asset: str = "scene.ply"
    selection_authority: Literal["ply"] = "ply"


class Manifest(BaseModel):
    asset_version: str = "0.1.0"
    scene_id: str
    capture: CaptureMetadata | dict[str, Any] = Field(default_factory=dict)
    source_video: str | None = None
    frames_dir: str = "frames/"
    reconstruction_dir: str = "reconstruction/"
    raw_splat_path: str = "scene.ply"
    segmentation_dir: str = "masks/"
    object_groups_dir: str = "object_groups/"
    objects_path: str = "objects.json"
    meshes_dir: str = "meshes/"
    viewer_dir: str = "viewer/"
    mobile_benchmarks_dir: str = "mobile_benchmarks/"
    benchmarks_path: str = "benchmarks.json"
    object_lifting_method: str | None = None
    object_lifting_degraded: bool = False
    warnings: list[str] = Field(default_factory=list)
    failures: list[str] = Field(default_factory=list)
    streaming_hints: StreamingHints = Field(default_factory=StreamingHints)
    uncertainty_notes: str | None = None
    runtime_hints: dict[str, Any] = Field(default_factory=dict)


class BBox3D(BaseModel):
    min: list[float]
    max: list[float]
    center: list[float] | None = None


class ObjectEntry(BaseModel):
    id: str
    label: str
    confidence: float | None = None
    coverage: float | None = None
    source_frames: list[str] = Field(default_factory=list)
    source_masks: list[str] = Field(default_factory=list)
    splat_count: int = 0
    bbox_3d: BBox3D | None = None
    mesh_path: str | None = None
    mesh_status: str | None = None
    mesh_method: str | None = None
    notes: str | None = None
    material_hints: dict[str, Any] | None = None
    uncertainty: float | None = None
    indices_path: str | None = None


class ObjectsFile(BaseModel):
    objects: list[ObjectEntry] = Field(default_factory=list)
    lifting_method: str | None = None
    degraded: bool = False
