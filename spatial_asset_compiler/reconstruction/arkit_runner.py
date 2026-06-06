"""ARKit reconstruction: write transforms.json without COLMAP."""

from __future__ import annotations

import json
import shutil
import time
from pathlib import Path
from typing import Any

import numpy as np

from spatial_asset_compiler.config import PipelineState
from spatial_asset_compiler.reconstruction.arkit_frustum_preview import write_frustum_preview_html
from spatial_asset_compiler.reconstruction.arkit_to_nerfstudio import (
    arkit_c2w_to_nerfstudio,
    arkit_transform_to_matrix,
    build_transforms_json,
    camera_position,
    first_pose_debug_payload,
    rotation_angle_deg,
)


def _pose_summary(rec: dict[str, Any]) -> dict[str, Any]:
    c2w = arkit_c2w_to_nerfstudio(arkit_transform_to_matrix(rec["transform"]))
    return {
        "position": camera_position(c2w).tolist(),
        "transform_matrix": c2w.tolist(),
        "frame": rec["output_frame"],
    }


def _build_pose_debug_report(
    state: PipelineState,
    accepted: list[dict[str, Any]],
    rejected_by_reason: dict[str, int],
) -> dict[str, Any]:
    profile = state.profile
    positions = []
    steps_m: list[float] = []
    steps_deg: list[float] = []
    c2ws = []
    for rec in accepted:
        c2w = arkit_c2w_to_nerfstudio(arkit_transform_to_matrix(rec["transform"]))
        c2ws.append(c2w)
        positions.append(camera_position(c2w))

    for i in range(1, len(c2ws)):
        steps_m.append(float(np.linalg.norm(positions[i] - positions[i - 1])))
        steps_deg.append(rotation_angle_deg(c2ws[i - 1], c2ws[i]))

    if positions:
        arr = np.stack(positions)
        pmin = arr.min(axis=0).tolist()
        pmax = arr.max(axis=0).tolist()
        extent = (arr.max(axis=0) - arr.min(axis=0)).tolist()
    else:
        pmin = pmax = extent = [0, 0, 0]

    warnings: list[str] = []
    for reason, count in rejected_by_reason.items():
        if count:
            warnings.append(f"{count} frames rejected: {reason}")

    return {
        "capture_mode": "arkit",
        "colmap_skipped": True,
        "accepted_count": len(accepted),
        "rejected_count": sum(rejected_by_reason.values()),
        "rejected_by_reason": rejected_by_reason,
        "profile_ar_max_frames": profile.ar_max_frames,
        "capped_by_profile": state.benchmarks.get("ar_capped_by_profile", False),
        "first_pose": _pose_summary(accepted[0]) if accepted else None,
        "last_pose": _pose_summary(accepted[-1]) if accepted else None,
        "pose_bounds": {"min": pmin, "max": pmax, "extent_m": extent},
        "average_camera_step_m": float(np.mean(steps_m)) if steps_m else 0.0,
        "average_rotation_step_deg": float(np.mean(steps_deg)) if steps_deg else 0.0,
        "warnings": warnings,
    }


def run_arkit_reconstruction(state: PipelineState) -> dict:
    p = state.paths
    t0 = time.perf_counter()
    accepted: list[dict[str, Any]] = state.benchmarks.get("arkit_accepted_poses") or []
    if not accepted:
        raise RuntimeError(
            "No ARKit accepted poses in benchmarks. Run ingest_arkit first."
        )

    out = p.reconstruction_dir
    ns_data = out / "ns_processed"
    images_dir = ns_data / "images"
    images_dir.mkdir(parents=True, exist_ok=True)

    frames_dir = p.frames_dir
    for rec in accepted:
        src = frames_dir / rec["output_frame"]
        dest = images_dir / rec["output_frame"]
        if not dest.exists():
            try:
                dest.symlink_to(src.resolve())
            except OSError:
                shutil.copy2(src, dest)

    transforms_data = build_transforms_json(accepted)
    transforms_path = ns_data / "transforms.json"
    transforms_path.write_text(json.dumps(transforms_data, indent=2), encoding="utf-8")
    canonical = out / "transforms.json"
    shutil.copy2(transforms_path, canonical)

    rejected = state.benchmarks.get("ar_rejected_by_reason", {})
    debug_report = _build_pose_debug_report(state, accepted, rejected)
    debug_path = out / "arkit_pose_debug.json"
    debug_path.write_text(json.dumps(debug_report, indent=2), encoding="utf-8")

    first_debug = first_pose_debug_payload(accepted[0])
    first_path = out / "first_pose_debug.json"
    first_path.write_text(json.dumps(first_debug, indent=2), encoding="utf-8")

    preview_path = out / "arkit_frustum_preview.html"
    try:
        write_frustum_preview_html(accepted, preview_path)
    except Exception as e:
        state.warnings.append(f"arkit_frustum_preview: {e}")

    duration = time.perf_counter() - t0
    registered = len(transforms_data.get("frames", []))
    meta = {
        "success": registered > 0,
        "colmap_skipped": True,
        "registered_frames": registered,
        "transforms_path": str(canonical),
        "reconstruction_time_s": duration,
        "output_dir": str(ns_data),
        "arkit_pose_debug_path": str(debug_path),
        "first_pose_debug_path": str(first_path),
        "frustum_preview_path": str(preview_path) if preview_path.exists() else None,
    }
    state.benchmarks.setdefault("reconstruction", {})
    state.benchmarks["reconstruction"].update(meta)
    state.benchmarks["colmap_skipped"] = True
    state.benchmarks["arkit_pose_debug_path"] = str(debug_path)

    if not meta["success"]:
        raise RuntimeError("ARKit reconstruction produced zero registered frames")
    return meta
