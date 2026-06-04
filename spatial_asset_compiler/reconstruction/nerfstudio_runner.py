"""Nerfstudio / COLMAP reconstruction via ns-process-data."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from spatial_asset_compiler.config import PipelineState, THIRD_PARTY
from spatial_asset_compiler.utils.subprocess_runner import CommandError, run_command


def _find_ns_process_data() -> str:
    import shutil as sh

    exe = sh.which("ns-process-data")
    if exe:
        return exe
    raise RuntimeError(
        "ns-process-data not found. Run: scripts/setup_env.sh\n"
        "Install nerfstudio in spatial-asset-clean from third_party/nerfstudio"
    )


def run_reconstruction(state: PipelineState) -> dict:
    p = state.paths
    frames_dir = p.frames_dir
    if not frames_dir.exists() or not list(frames_dir.glob("frame_*.jpg")):
        raise FileNotFoundError(f"No frames in {frames_dir}. Run ingest stage first.")

    out = p.reconstruction_dir
    out.mkdir(parents=True, exist_ok=True)

    # ns-process-data images expects images/ folder
    images_dir = out / "images"
    images_dir.mkdir(exist_ok=True)
    for f in sorted(frames_dir.glob("frame_*.jpg")):
        dest = images_dir / f.name
        if not dest.exists():
            try:
                dest.symlink_to(f.resolve())
            except OSError:
                shutil.copy2(f, dest)

    ns_data = out / "ns_processed"
    cmd = [
        _find_ns_process_data(),
        "images",
        "--data",
        str(out),
        "--output-dir",
        str(ns_data),
    ]
    log = p.logs_dir / "reconstruction.log"
    try:
        result = run_command(
            cmd,
            log_path=log,
            hint="Ensure COLMAP is installed: sudo apt install colmap",
            timeout_s=None,
        )
    except CommandError as e:
        state.failures.append(f"reconstruction: {e}")
        raise

    # Locate transforms.json
    transforms = None
    for candidate in [
        ns_data / "transforms.json",
        out / "transforms.json",
        ns_data / "sparse" / "0",
    ]:
        if (ns_data / "transforms.json").exists():
            transforms = ns_data / "transforms.json"
            break
    for root in [ns_data, out]:
        for t in root.rglob("transforms.json"):
            transforms = t
            break
        if transforms:
            break

    registered = 0
    if transforms and transforms.exists():
        data = json.loads(transforms.read_text(encoding="utf-8"))
        registered = len(data.get("frames", []))
        # Copy to canonical location
        canonical = out / "transforms.json"
        if transforms != canonical:
            shutil.copy2(transforms, canonical)
        transforms = canonical

    colmap_ok = (ns_data / "colmap").exists() or (out / "sparse").exists() or registered > 0
    meta = {
        "success": colmap_ok and registered > 0,
        "registered_frames": registered,
        "transforms_path": str(transforms) if transforms else None,
        "reconstruction_time_s": result.duration_s,
        "output_dir": str(ns_data if ns_data.exists() else out),
    }
    state.benchmarks.setdefault("reconstruction", {})
    state.benchmarks["reconstruction"].update(meta)
    if not meta["success"]:
        raise RuntimeError(
            f"COLMAP/reconstruction failed. registered_frames={registered}. See {log}"
        )
    return meta
