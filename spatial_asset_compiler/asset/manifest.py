"""Build and write manifest.json."""

from __future__ import annotations

import json
from pathlib import Path

from spatial_asset_compiler.asset.schemas import CaptureMetadata, Manifest, StreamingHints
from spatial_asset_compiler.config import ASSET_VERSION, PipelineState


def build_manifest(state: PipelineState) -> Manifest:
    p = state.paths
    capture_meta: CaptureMetadata | dict = {}
    cap_json = p.capture_dir / "capture.json"
    if cap_json.exists():
        raw = json.loads(cap_json.read_text(encoding="utf-8"))
        try:
            capture_meta = CaptureMetadata.model_validate(raw)
        except Exception:
            capture_meta = raw

    hints = StreamingHints(
        preview_asset="scene.ply",
        selection_authority="ply",
    )

    video_files = list(p.capture_dir.glob("video.*"))
    source_video = str(video_files[0].relative_to(p.capture_dir)) if video_files else None

    return Manifest(
        asset_version=ASSET_VERSION,
        scene_id=p.scene_id,
        capture=capture_meta,
        source_video=source_video,
        frames_dir="frames/",
        reconstruction_dir="reconstruction/",
        raw_splat_path="scene.ply",
        object_lifting_method=state.benchmarks.get("object_lifting_method"),
        object_lifting_degraded=state.benchmarks.get("object_lifting_degraded", False),
        warnings=state.warnings,
        failures=state.failures,
        streaming_hints=hints,
        runtime_hints={
            "profile": state.profile.name,
            "gpu_note": "RTX 2080 Ti 11GB — use dev profile for faster iteration",
        },
    )


def write_manifest(state: PipelineState) -> Path:
    manifest = build_manifest(state)
    state.paths.manifest_path.write_text(
        manifest.model_dump_json(indent=2), encoding="utf-8"
    )
    return state.paths.manifest_path
