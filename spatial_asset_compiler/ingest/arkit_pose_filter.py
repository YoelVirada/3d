"""Pose quality filtering and frame cap for ARKit captures."""

from __future__ import annotations

from collections import Counter
from typing import Any

import numpy as np

from spatial_asset_compiler.capture.schema import ARFramePose
from spatial_asset_compiler.config import ProfileConfig
from spatial_asset_compiler.reconstruction.arkit_to_nerfstudio import (
    arkit_c2w_to_nerfstudio,
    arkit_transform_to_matrix,
    camera_position,
    rotation_angle_deg,
)


def uniform_subsample(items: list[Any], max_count: int) -> list[Any]:
    if len(items) <= max_count:
        return items
    idx = np.linspace(0, len(items) - 1, max_count, dtype=int)
    return [items[i] for i in idx]


def filter_arkit_poses(
    poses: list[ARFramePose],
    profile: ProfileConfig,
) -> tuple[list[dict[str, Any]], Counter[str]]:
    """Return accepted pose dicts (with output_frame) and rejection reason counts."""
    rejected: Counter[str] = Counter()
    sorted_poses = sorted(poses, key=lambda p: p.timestamp_s)
    accepted: list[dict[str, Any]] = []
    last_accepted: dict[str, Any] | None = None
    frame_idx = 0

    for pose in sorted_poses:
        if pose.tracking_state != "normal":
            rejected["tracking_not_normal"] += 1
            continue

        if last_accepted is not None:
            dt = pose.timestamp_s - float(last_accepted["timestamp_s"])
            if dt < profile.ar_min_time_delta_s:
                rejected["too_close_in_time"] += 1
                continue

            c2w_prev = arkit_c2w_to_nerfstudio(
                arkit_transform_to_matrix(last_accepted["transform"])
            )
            c2w_cur = arkit_c2w_to_nerfstudio(
                arkit_transform_to_matrix(pose.transform)
            )
            pos_prev = camera_position(c2w_prev)
            pos_cur = camera_position(c2w_cur)
            dist = float(np.linalg.norm(pos_cur - pos_prev))
            if dist < profile.ar_min_translation_m:
                rejected["too_close_in_space"] += 1
                continue
            if dist > profile.ar_max_translation_jump_m:
                rejected["translation_jump"] += 1
                continue
            angle = rotation_angle_deg(c2w_prev, c2w_cur)
            if angle > profile.ar_max_rotation_jump_deg:
                rejected["rotation_jump"] += 1
                continue

        frame_idx += 1
        rec = {
            "frame": pose.frame,
            "output_frame": f"frame_{frame_idx:05d}.jpg",
            "timestamp_s": pose.timestamp_s,
            "tracking_state": pose.tracking_state,
            "transform": pose.transform,
            "intrinsics": pose.intrinsics,
            "width": pose.width,
            "height": pose.height,
        }
        accepted.append(rec)
        last_accepted = rec

    capped_by_profile = False
    if len(accepted) > profile.ar_max_frames:
        accepted = uniform_subsample(accepted, profile.ar_max_frames)
        capped_by_profile = True
        for i, rec in enumerate(accepted, start=1):
            rec["output_frame"] = f"frame_{i:05d}.jpg"

    return accepted, rejected, capped_by_profile
