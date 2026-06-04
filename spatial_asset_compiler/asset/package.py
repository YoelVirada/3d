"""Finalize spatial asset package."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from spatial_asset_compiler.asset.manifest import write_manifest
from spatial_asset_compiler.asset.schemas import ObjectsFile
from spatial_asset_compiler.benchmarks.report import BenchmarkReport
from spatial_asset_compiler.config import PipelineState
from spatial_asset_compiler.viewer.export_viewer_assets import export_viewer_assets


def _dir_size_mb(path: Path) -> float:
    total = 0
    if not path.exists():
        return 0.0
    for f in path.rglob("*"):
        if f.is_file():
            total += f.stat().st_size
    return total / (1024 * 1024)


def finalize_package(state: PipelineState) -> None:
    p = state.paths
    p.output_dir.mkdir(parents=True, exist_ok=True)

    # objects.json
    objects_path = p.objects_path
    if not objects_path.exists():
        ObjectsFile(objects=[], lifting_method=None).model_dump_json(indent=2)
        objects_path.write_text(
            ObjectsFile(objects=[], lifting_method=None).model_dump_json(indent=2),
            encoding="utf-8",
        )

    # benchmarks
    report = BenchmarkReport(p.benchmarks_path)
    report.data.update(state.benchmarks)
    if p.scene_ply.exists():
        report.set("raw_splat_size_mb", p.scene_ply.stat().st_size / (1024 * 1024))
    report.set("output_package_size_mb", _dir_size_mb(p.output_dir))
    report.save()

    write_manifest(state)

    # mobile benchmark templates
    mob = p.mobile_benchmarks_dir
    mob.mkdir(parents=True, exist_ok=True)
    notes = {
        "instructions": [
            "1. Run capture server on WSL: scripts/run_capture_server.sh",
            "2. Upload video from iPhone app to http://<wsl-ip>:8787/captures/<scene_id>",
            "3. Run pipeline: python -m spatial_asset_compiler.run --scene-id <scene_id>",
            "4. Serve viewer: cd apps/viewer-web && npm run dev",
            "5. Open on iPhone Safari: http://<host>:5173/?package=/exports/<scene_id>/manifest.json&benchmark=1",
        ],
        "webgpu_note": "Safari iOS 26+ has default WebGPU. Older iOS uses WebGL fallback in viewer.",
        "safari_webgpu_min_ios": "26",
    }
    (mob / "ios_capture_notes.json").write_text(
        json.dumps(notes, indent=2), encoding="utf-8"
    )
    template = {
        "mobile_load_time_ms": None,
        "mobile_fps": None,
        "webgpu_available": None,
        "device": None,
        "instructions": "Fill via viewer Export Benchmark on device",
    }
    (mob / "ios_viewer_results.template.json").write_text(
        json.dumps(template, indent=2), encoding="utf-8"
    )

    try:
        export_viewer_assets(state)
    except Exception as e:
        state.warnings.append(f"viewer_export: {e}")
        write_manifest(state)
