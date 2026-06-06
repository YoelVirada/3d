"""Copy slim asset package into exports viewer/ for static hosting."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from spatial_asset_compiler.config import PipelineState


def export_viewer_assets(state: PipelineState) -> Path:
    p = state.paths
    viewer = p.viewer_dir
    viewer.mkdir(parents=True, exist_ok=True)

    for name in ["manifest.json", "objects.json", "benchmarks.json"]:
        src = p.output_dir / name
        if src.exists():
            shutil.copy2(src, viewer / name)

    if p.scene_ply.exists():
        shutil.copy2(p.scene_ply, viewer / "scene.ply")

    runtime = p.runtime_dir
    if runtime.exists():
        vruntime = viewer / "runtime"
        vruntime.mkdir(parents=True, exist_ok=True)
        for f in runtime.rglob("*"):
            if f.is_file():
                rel = f.relative_to(runtime)
                dest = vruntime / rel
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(f, dest)

    og = p.object_groups_dir
    if og.exists():
        vog = viewer / "object_groups"
        vog.mkdir(exist_ok=True)
        for f in og.glob("obj_*.indices"):
            shutil.copy2(f, vog / f.name)
        if (og / "object_groups.json").exists():
            shutil.copy2(og / "object_groups.json", vog / "object_groups.json")

    readme = {
        "entry": f"http://localhost:5173/?package=/{p.output_dir.relative_to(p.output_dir.parent.parent)}/manifest.json",
        "note": "Use apps/viewer-web with package= query pointing at manifest.json",
    }
    (viewer / "README.json").write_text(json.dumps(readme, indent=2), encoding="utf-8")
    return viewer
