"""Per-object mesh extraction (Open3D) + optional SuGaR scene mesh."""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

import numpy as np

from spatial_asset_compiler.config import PipelineState, THIRD_PARTY
from spatial_asset_compiler.splats.io import load_splat_positions


def run_mesh_extraction(state: PipelineState) -> dict:
    p = state.paths
    p.meshes_dir.mkdir(parents=True, exist_ok=True)
    top_n = state.profile.mesh_top_n
    per_object_results = []

    if not p.objects_path.exists():
        state.warnings.append("mesh: no objects.json")
        return {"per_object": [], "success_count": 0}

    data = json.loads(p.objects_path.read_text(encoding="utf-8"))
    objects = sorted(
        data.get("objects", []),
        key=lambda o: o.get("splat_count", 0),
        reverse=True,
    )[:top_n]

    positions = load_splat_positions(p.scene_ply)
    success_count = 0

    for obj in objects:
        oid = obj["id"]
        idx_path = p.object_groups_dir / f"{oid}.indices"
        t0 = time.perf_counter()
        status = "failed"
        mesh_path = None
        method = "open3d_poisson"
        reason = None

        if idx_path.exists():
            inds = np.frombuffer(idx_path.read_bytes(), dtype=np.uint32)
            pts = positions[inds]
            if len(pts) >= 50:
                try:
                    mesh_path = _mesh_open3d(pts, p.meshes_dir / f"{oid}.ply")
                    if mesh_path and mesh_path.exists():
                        status = "success"
                        success_count += 1
                except Exception as e:
                    reason = str(e)
            else:
                reason = f"too few points: {len(pts)}"
        else:
            reason = "missing indices"

        per_object_results.append(
            {
                "object_id": oid,
                "status": status,
                "mesh_path": f"meshes/{oid}.ply" if mesh_path else None,
                "method": method,
                "time_s": time.perf_counter() - t0,
                "reason": reason,
            }
        )
        obj["mesh_path"] = f"meshes/{oid}.ply" if status == "success" else None
        obj["mesh_status"] = status
        obj["mesh_method"] = method

    data["objects"] = objects
    # merge back full object list
    full = json.loads(p.objects_path.read_text(encoding="utf-8"))
    updated = {o["id"]: o for o in objects}
    for i, o in enumerate(full.get("objects", [])):
        if o["id"] in updated:
            full["objects"][i] = {**o, **updated[o["id"]]}
    p.objects_path.write_text(json.dumps(full, indent=2), encoding="utf-8")

    sugar_path = None
    if state.profile.run_sugar_scene_mesh:
        sugar_path = _run_sugar_scene(state)

    meta = {
        "per_object": per_object_results,
        "success_count": success_count,
        "top_n": top_n,
        "scene_sugar_mesh": str(sugar_path) if sugar_path else None,
    }
    state.benchmarks["mesh"] = meta
    if success_count == 0:
        state.warnings.append("mesh: no per-object mesh succeeded among top-N")
    return meta


def _mesh_open3d(points: np.ndarray, out_path: Path) -> Path | None:
    import open3d as o3d

    pcd = o3d.geometry.PointCloud()
    pcd.points = o3d.utility.Vector3dVector(points.astype(np.float64))
    pcd.estimate_normals(
        search_param=o3d.geometry.KDTreeSearchParamHybrid(radius=0.05, max_nn=30)
    )
    mesh, _ = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(pcd, depth=7)
    mesh = mesh.remove_degenerate_triangles().remove_duplicated_triangles()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    o3d.io.write_triangle_mesh(str(out_path), mesh)
    return out_path if out_path.exists() else None


def _run_sugar_scene(state: PipelineState) -> Path | None:
    p = state.paths
    sugar_root = THIRD_PARTY / "SuGaR"
    log = p.logs_dir / "sugar_scene.log"
    if not sugar_root.exists():
        log.write_text("SuGaR not installed\n")
        return None
    out = p.meshes_dir / "scene_sugar.ply"
    cmd = [
        "conda",
        "run",
        "-n",
        "sugar-mesh",
        "--no-capture-output",
        "python",
        str(Path(__file__).parent / "sugar_wrapper.py"),
        "--sugar-root",
        str(sugar_root),
        "--data",
        str(p.reconstruction_dir),
        "--output",
        str(out),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
    log.write_text(proc.stdout + proc.stderr, encoding="utf-8")
    return out if out.exists() else None
