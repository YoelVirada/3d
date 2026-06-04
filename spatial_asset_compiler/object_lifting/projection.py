"""Vote-based emergency object lifting via mask projection."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from spatial_asset_compiler.asset.schemas import BBox3D, ObjectEntry, ObjectsFile
from spatial_asset_compiler.config import PipelineState
from spatial_asset_compiler.splats.io import load_splat_positions


def _load_transforms(rec_dir: Path) -> dict | None:
    for t in [rec_dir / "transforms.json", *rec_dir.rglob("transforms.json")]:
        if t.exists():
            return json.loads(t.read_text(encoding="utf-8"))
    return None


def _project_point(cam: dict, xyz: np.ndarray) -> tuple[float, float, float]:
    """Project world point to image uv; returns (u, v, depth)."""
    import numpy as np

    c2w = np.array(cam["transform_matrix"], dtype=np.float64)
    w2c = np.linalg.inv(c2w)
    p4 = np.array([xyz[0], xyz[1], xyz[2], 1.0])
    cam_p = w2c @ p4
    z = cam_p[2]
    if z <= 1e-6:
        return -1, -1, z
    fx = cam.get("fl_x", cam.get("fx", 500))
    fy = cam.get("fl_y", cam.get("fy", 500))
    cx = cam.get("cx", cam.get("w", 640) / 2)
    cy = cam.get("cy", cam.get("h", 480) / 2)
    u = fx * cam_p[0] / z + cx
    v = fy * cam_p[1] / z + cy
    return float(u), float(v), float(z)


def run_vote_fallback(state: PipelineState) -> dict:
    p = state.paths
    ply = p.scene_ply
    if not ply.exists():
        raise FileNotFoundError("scene.ply required for vote fallback")

    positions = load_splat_positions(ply)
    n = len(positions)
    transforms = _load_transforms(p.reconstruction_dir)
    if not transforms:
        raise FileNotFoundError("transforms.json required for vote fallback")

    index_path = p.masks_dir / "index.json"
    if not index_path.exists():
        raise FileNotFoundError("masks/index.json required")

    import cv2

    mask_index = json.loads(index_path.read_text(encoding="utf-8"))["masks"]
    frames_by_name = {f["file_path"].split("/")[-1]: f for f in transforms.get("frames", []) if "file_path" in f}
    # build frame name map from file_path
    frame_cams: dict[str, dict] = {}
    for fr in transforms.get("frames", []):
        fp = fr.get("file_path", "")
        name = Path(fp).name
        if not name and "frame" in str(fp):
            name = Path(fp).stem + ".jpg"
        frame_cams[name] = fr
        # also match frame_00001.jpg style
        stem = Path(fp).stem
        frame_cams[stem + ".jpg"] = fr

    votes: dict[str, np.ndarray] = {}
    for mi, m in enumerate(mask_index[:50]):
        oid = f"mask_{mi:03d}"
        votes[oid] = np.zeros(n, dtype=np.float32)
        frame_name = m["frame"]
        cam = frame_cams.get(frame_name)
        if cam is None:
            continue
        mask_path = p.masks_dir / m["path"]
        if not mask_path.exists():
            continue
        mask = cv2.imread(str(mask_path), cv2.IMREAD_GRAYSCALE)
        if mask is None:
            continue
        h, w = mask.shape[:2]
        for i in range(n):
            u, v, z = _project_point(cam, positions[i])
            if z <= 0:
                continue
            ui, vi = int(round(u)), int(round(v))
            if 0 <= ui < w and 0 <= vi < h and mask[vi, ui] > 127:
                votes[oid][i] += 1.0

    # cluster masks into objects by merging highly overlapping vote winners
    assignments = np.full(n, -1, dtype=np.int32)
    object_ids: list[str] = []
    for oid, v in sorted(votes.items(), key=lambda x: -x[1].sum()):
        if v.sum() < 10:
            continue
        unassigned = assignments < 0
        pick = (v > 0) & unassigned
        if pick.sum() < 10:
            continue
        obj_id = f"obj_{len(object_ids)+1:03d}"
        object_ids.append(obj_id)
        assignments[pick] = len(object_ids) - 1

    og_dir = p.object_groups_dir
    og_dir.mkdir(parents=True, exist_ok=True)
    groups_meta = []
    objects: list[ObjectEntry] = []
    for idx, obj_id in enumerate(object_ids):
        inds = np.where(assignments == idx)[0].astype(np.uint32)
        if len(inds) < 10:
            continue
        ind_path = og_dir / f"{obj_id}.indices"
        ind_path.write_bytes(inds.tobytes())
        pts = positions[inds]
        bbox = BBox3D(
            min=pts.min(axis=0).tolist(),
            max=pts.max(axis=0).tolist(),
            center=pts.mean(axis=0).tolist(),
        )
        groups_meta.append({"id": obj_id, "count": len(inds), "indices": ind_path.name})
        objects.append(
            ObjectEntry(
                id=obj_id,
                label=obj_id,
                confidence=float(len(inds) / n),
                coverage=float(len(inds) / n),
                splat_count=len(inds),
                bbox_3d=bbox,
                indices_path=f"object_groups/{obj_id}.indices",
                notes="vote_fallback emergency lifting",
            )
        )

    (og_dir / "object_groups.json").write_text(
        json.dumps({"groups": groups_meta}, indent=2), encoding="utf-8"
    )
    of = ObjectsFile(objects=objects, lifting_method="vote_fallback", degraded=True)
    p.objects_path.write_text(of.model_dump_json(indent=2), encoding="utf-8")

    return {
        "lifting_method": "vote_fallback",
        "object_count": len(objects),
        "degraded": True,
    }
