"""ARKit capture ingest: pose filter, frame copy, metadata."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from spatial_asset_compiler.capture.schema import ARFramePose, ARManifest, CapturePackage
from spatial_asset_compiler.config import PipelineState
from spatial_asset_compiler.ingest.arkit_pose_filter import filter_arkit_poses


def _load_poses(capture_dir: Path) -> list[ARFramePose]:
    poses_path = capture_dir / "ar" / "poses.json"
    if not poses_path.exists():
        raise FileNotFoundError(f"Missing ARKit poses: {poses_path}")
    raw = json.loads(poses_path.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise ValueError("ar/poses.json must be a JSON array")
    return [ARFramePose.model_validate(p) for p in raw]


def ingest_arkit(state: PipelineState) -> dict:
    p = state.paths
    capture_dir = p.capture_dir
    ar_frames_src = capture_dir / "ar" / "frames"
    if not ar_frames_src.is_dir():
        raise FileNotFoundError(f"Missing ARKit frames dir: {ar_frames_src}")

    poses = _load_poses(capture_dir)
    accepted, rejected, capped_by_profile = filter_arkit_poses(poses, state.profile)
    if not accepted:
        raise RuntimeError(
            "No ARKit frames passed quality filter. "
            f"Rejected: {dict(rejected)}"
        )

    frames_dir = p.frames_dir
    frames_dir.mkdir(parents=True, exist_ok=True)
    for old in frames_dir.glob("frame_*.jpg"):
        old.unlink()

    for rec in accepted:
        src = ar_frames_src / rec["frame"]
        if not src.exists():
            raise FileNotFoundError(f"Missing AR frame image: {src}")
        shutil.copy2(src, frames_dir / rec["output_frame"])

    cap_json = capture_dir / "capture.json"
    capture_meta: dict = {}
    if cap_json.exists():
        capture_meta = json.loads(cap_json.read_text(encoding="utf-8"))

    rejected_total = sum(rejected.values())
    meta = {
        "capture_mode": "arkit",
        "frame_count": len(accepted),
        "ar_frame_count": len(accepted),
        "ar_frames_rejected": rejected_total,
        "ar_rejected_by_reason": dict(rejected),
        "ar_capped_by_profile": capped_by_profile,
        "profile_ar_max_frames": state.profile.ar_max_frames,
        "source_poses": len(poses),
        "resolution": f"{accepted[0]['width']}x{accepted[0]['height']}",
        "capture": capture_meta,
    }
    state.benchmarks["capture_mode"] = "arkit"
    state.benchmarks["ar_frame_count"] = len(accepted)
    state.benchmarks["ar_frames_rejected"] = rejected_total
    state.benchmarks["ar_rejected_by_reason"] = dict(rejected)
    state.benchmarks["ar_capped_by_profile"] = capped_by_profile
    state.benchmarks["arkit_accepted_poses"] = accepted

    (p.output_dir / "frames_metadata.json").write_text(
        json.dumps(meta, indent=2), encoding="utf-8"
    )
    state.benchmarks.setdefault("ingest", {})
    state.benchmarks["ingest"].update(
        {
            "frame_count": len(accepted),
            "capture_mode": "arkit",
            "ar_frame_count": len(accepted),
            "ar_frames_rejected": rejected_total,
        }
    )
    return meta
