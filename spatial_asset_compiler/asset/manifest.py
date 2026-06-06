"""Build and write manifest.json."""

from __future__ import annotations

import json
from pathlib import Path

from spatial_asset_compiler.asset.schemas import CaptureMetadata, Manifest, RuntimeAssets, StreamingHints
from spatial_asset_compiler.config import ASSET_VERSION, PipelineState

VIEWER_SUPPORTED_SPLAT_SUFFIXES = (".ply",)


def _load_runtime_assets(state: PipelineState) -> tuple[RuntimeAssets | None, str | None]:
    runtime_meta = state.benchmarks.get("runtime_asset")
    sources: list[dict] = []
    if isinstance(runtime_meta, dict):
        sources.append(runtime_meta)
    runtime_json = state.paths.runtime_dir / "runtime_assets.json"
    if runtime_json.exists():
        try:
            sources.append(json.loads(runtime_json.read_text(encoding="utf-8")))
        except Exception:
            pass

    for raw in sources:
        outputs = raw.get("outputs") or {}
        ra = RuntimeAssets(
            spz=outputs.get("spz"),
            sog=outputs.get("sog"),
            preview=outputs.get("preview"),
            lod=outputs.get("lod"),
        )
        viewer_preview = raw.get("viewer_supported_preview")
        if any((ra.spz, ra.sog, ra.preview, ra.lod)):
            return ra, viewer_preview
    return None, None


def _viewer_preview_asset(
    runtime_assets: RuntimeAssets | None,
    viewer_supported_preview: str | None,
) -> str:
    if viewer_supported_preview and viewer_supported_preview.endswith(
        VIEWER_SUPPORTED_SPLAT_SUFFIXES
    ):
        return viewer_supported_preview
    if runtime_assets and runtime_assets.preview:
        preview = runtime_assets.preview
        if preview.endswith(VIEWER_SUPPORTED_SPLAT_SUFFIXES):
            return preview
    return "scene.ply"


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

    runtime_assets, viewer_supported_preview = _load_runtime_assets(state)
    hints = StreamingHints(
        preview_asset=_viewer_preview_asset(runtime_assets, viewer_supported_preview),
        lod_supported=bool(runtime_assets and runtime_assets.lod),
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
        runtime_assets=runtime_assets,
        object_lifting_method=state.benchmarks.get("object_lifting_method"),
        object_lifting_degraded=state.benchmarks.get("object_lifting_degraded", False),
        warnings=state.warnings,
        failures=state.failures,
        streaming_hints=hints,
        runtime_hints={
            "profile": state.profile.name,
            "gpu_note": "RTX 2080 Ti 11GB — use dev profile for faster iteration",
            "capture_mode": state.benchmarks.get("capture_mode"),
            "colmap_skipped": state.benchmarks.get("colmap_skipped"),
            "ar_frame_count": state.benchmarks.get("ar_frame_count"),
            "ar_frames_rejected": state.benchmarks.get("ar_frames_rejected"),
            "arkit_pose_debug_path": state.benchmarks.get("arkit_pose_debug_path"),
            "runtime_assets_path": "runtime/runtime_assets.json"
            if (p.runtime_dir / "runtime_assets.json").exists()
            else None,
        },
    )


def write_manifest(state: PipelineState) -> Path:
    manifest = build_manifest(state)
    state.paths.manifest_path.write_text(
        manifest.model_dump_json(indent=2), encoding="utf-8"
    )
    return state.paths.manifest_path
