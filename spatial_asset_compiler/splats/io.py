"""PLY / splat I/O helpers."""

from __future__ import annotations

from pathlib import Path

import numpy as np


def count_gaussians_ply(ply_path: Path) -> int:
    from plyfile import PlyData

    ply = PlyData.read(str(ply_path))
    return len(ply["vertex"].data)


def load_splat_positions(ply_path: Path) -> np.ndarray:
    from plyfile import PlyData

    ply = PlyData.read(str(ply_path))
    v = ply["vertex"].data
    names = v.dtype.names or ()
    if all(k in names for k in ("x", "y", "z")):
        return np.stack([v["x"], v["y"], v["z"]], axis=1).astype(np.float64)
    # fallback first three fields
    cols = list(names)[:3]
    return np.stack([v[c] for c in cols], axis=1).astype(np.float64)


def file_size_mb(path: Path) -> float:
    if not path.exists():
        return 0.0
    return path.stat().st_size / (1024 * 1024)
