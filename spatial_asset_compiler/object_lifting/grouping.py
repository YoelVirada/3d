"""Normalize object group outputs from research tools."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from spatial_asset_compiler.asset.schemas import BBox3D, ObjectEntry, ObjectsFile
from spatial_asset_compiler.config import PipelineState
from spatial_asset_compiler.splats.io import load_splat_positions


def write_object_groups(
    state: PipelineState,
    assignments: np.ndarray,
    lifting_method: str,
    labels: dict[str, str] | None = None,
) -> dict:
    """assignments: int array length N, -1 = unassigned."""
    p = state.paths
    positions = load_splat_positions(p.scene_ply)
    n = len(positions)
    og_dir = p.object_groups_dir
    og_dir.mkdir(parents=True, exist_ok=True)
    labels = labels or {}

    unique = sorted(set(int(a) for a in assignments if a >= 0))
    groups_meta = []
    objects: list[ObjectEntry] = []

    for gid in unique:
        inds = np.where(assignments == gid)[0].astype(np.uint32)
        if len(inds) < 5:
            continue
        obj_id = f"obj_{gid+1:03d}"
        ind_path = og_dir / f"{obj_id}.indices"
        ind_path.write_bytes(inds.tobytes())
        pts = positions[inds]
        bbox = BBox3D(
            min=pts.min(axis=0).tolist(),
            max=pts.max(axis=0).tolist(),
            center=pts.mean(axis=0).tolist(),
        )
        groups_meta.append({"id": obj_id, "group_id": gid, "count": len(inds)})
        objects.append(
            ObjectEntry(
                id=obj_id,
                label=labels.get(str(gid), obj_id),
                confidence=min(1.0, len(inds) / max(n * 0.05, 1)),
                coverage=len(inds) / n,
                splat_count=len(inds),
                bbox_3d=bbox,
                indices_path=f"object_groups/{obj_id}.indices",
            )
        )

    (og_dir / "object_groups.json").write_text(
        json.dumps({"groups": groups_meta, "method": lifting_method}, indent=2),
        encoding="utf-8",
    )
    of = ObjectsFile(objects=objects, lifting_method=lifting_method, degraded=False)
    p.objects_path.write_text(of.model_dump_json(indent=2), encoding="utf-8")
    return {"object_count": len(objects), "lifting_method": lifting_method}
