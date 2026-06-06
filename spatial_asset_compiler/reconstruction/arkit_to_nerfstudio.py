"""ARKit camera poses → Nerfstudio transforms.json convention.

ARKit provides camera-to-world 4×4 matrices in a right-handed Y-up world frame
(row-major when serialized from iOS). Nerfstudio expects ``transform_matrix`` per
frame in the same layout produced by Polycam mobile exports: row permutation of
the ARKit matrix (see upstream polycam_utils.py), with ``orientation_override``
equivalent to ``none``.

Do not apply COLMAP-specific row flips here; Polycam/ARKit mobile captures use
the direct remap only.
"""

from __future__ import annotations

from typing import Any

import numpy as np

CONVERSION_NOTES = (
    "Polycam-style row remap: NS rows [ARKit row2, ARKit row0, ARKit row1, bottom]. "
    "Intrinsics: fx=K[0][0], fy=K[1][1], cx=K[2][0], cy=K[2][1] from ARKit 3×3."
)


def arkit_transform_to_matrix(transform: list[list[float]]) -> np.ndarray:
    return np.asarray(transform, dtype=np.float64).reshape(4, 4)


def arkit_c2w_to_nerfstudio(arkit_c2w: np.ndarray) -> np.ndarray:
    """Convert ARKit camera-to-world 4×4 to Nerfstudio ``transform_matrix``."""
    t = np.asarray(arkit_c2w, dtype=np.float64)
    c2w = np.array(
        [
            t[2, :],
            t[0, :],
            t[1, :],
            [0.0, 0.0, 0.0, 1.0],
        ],
        dtype=np.float64,
    )
    return c2w


def camera_position(c2w: np.ndarray) -> np.ndarray:
    return c2w[:3, 3].copy()


def intrinsics_from_arkit(k: list[list[float]], width: int, height: int) -> dict[str, float]:
    mat = np.asarray(k, dtype=np.float64).reshape(3, 3)
    return {
        "fl_x": float(mat[0, 0]),
        "fl_y": float(mat[1, 1]),
        "cx": float(mat[2, 0]),
        "cy": float(mat[2, 1]),
        "w": float(width),
        "h": float(height),
    }


def rotation_angle_deg(c2w_a: np.ndarray, c2w_b: np.ndarray) -> float:
    ra = c2w_a[:3, :3]
    rb = c2w_b[:3, :3]
    r_rel = ra.T @ rb
    trace = float(np.clip((np.trace(r_rel) - 1.0) / 2.0, -1.0, 1.0))
    return float(np.degrees(np.arccos(trace)))


def build_transforms_json(
    accepted: list[dict[str, Any]],
    *,
    images_prefix: str = "./images",
) -> dict[str, Any]:
    """Build Nerfstudio-compatible transforms dict from accepted pose records."""
    if not accepted:
        raise ValueError("No accepted poses for transforms.json")

    first = accepted[0]
    intr = intrinsics_from_arkit(
        first["intrinsics"], int(first["width"]), int(first["height"])
    )
    out: dict[str, Any] = {
        "camera_model": "OPENCV",
        "orientation_override": "none",
        "fl_x": intr["fl_x"],
        "fl_y": intr["fl_y"],
        "cx": intr["cx"],
        "cy": intr["cy"],
        "w": int(intr["w"]),
        "h": int(intr["h"]),
        "frames": [],
    }

    for rec in accepted:
        arkit = arkit_transform_to_matrix(rec["transform"])
        c2w = arkit_c2w_to_nerfstudio(arkit)
        frame_name = rec["output_frame"]
        out["frames"].append(
            {
                "file_path": f"{images_prefix}/{frame_name}",
                "transform_matrix": c2w.tolist(),
            }
        )
    return out


def first_pose_debug_payload(first: dict[str, Any]) -> dict[str, Any]:
    arkit = arkit_transform_to_matrix(first["transform"])
    c2w = arkit_c2w_to_nerfstudio(arkit)
    intr = intrinsics_from_arkit(
        first["intrinsics"], int(first["width"]), int(first["height"])
    )
    return {
        "arkit_transform_raw": arkit.tolist(),
        "nerfstudio_transform_matrix": c2w.tolist(),
        "intrinsics_raw": first["intrinsics"],
        "intrinsics_used": intr,
        "conversion_notes": CONVERSION_NOTES,
    }
