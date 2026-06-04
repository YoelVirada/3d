#!/usr/bin/env python3
"""Assign splats to objects using SAM2 mask prompts (SAGA-adjacent prompt flow)."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def project(cam: dict, xyz: np.ndarray) -> tuple[float, float, float]:
    c2w = np.array(cam["transform_matrix"], dtype=np.float64)
    w2c = np.linalg.inv(c2w)
    p4 = np.array([xyz[0], xyz[1], xyz[2], 1.0])
    cam_p = w2c @ p4
    z = cam_p[2]
    if z <= 1e-6:
        return -1.0, -1.0, z
    fx = cam.get("fl_x", 500.0)
    fy = cam.get("fl_y", 500.0)
    cx = cam.get("cx", 320.0)
    cy = cam.get("cy", 240.0)
    u = fx * cam_p[0] / z + cx
    v = fy * cam_p[1] / z + cy
    return float(u), float(v), z


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ply", required=True)
    ap.add_argument("--transforms", required=True)
    ap.add_argument("--masks-index", required=True)
    ap.add_argument("--masks-dir", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    from plyfile import PlyData

    ply = PlyData.read(args.ply)
    v = ply["vertex"].data
    pos = np.stack([v["x"], v["y"], v["z"]], axis=1)
    n = len(pos)

    transforms = json.loads(Path(args.transforms).read_text())
    frame_cams = {}
    for fr in transforms.get("frames", []):
        name = Path(fr.get("file_path", "")).name
        frame_cams[name] = fr

    masks = json.loads(Path(args.masks_index).read_text())["masks"]
    assignments = np.full(n, -1, dtype=np.int32)
    obj_id = 0
    for mi, m in enumerate(masks):
        frame = m["frame"]
        cam = frame_cams.get(frame)
        if cam is None:
            continue
        mask = cv2.imread(str(Path(args.masks_dir) / m["path"]), cv2.IMREAD_GRAYSCALE)
        if mask is None:
            continue
        h, w = mask.shape
        hits = []
        for i in range(n):
            u, v, z = project(cam, pos[i])
            if z <= 0:
                continue
            ui, vi = int(round(u)), int(round(v))
            if 0 <= ui < w and 0 <= vi < h and mask[vi, ui] > 127:
                hits.append(i)
        if len(hits) < 20:
            continue
        for i in hits:
            if assignments[i] < 0:
                assignments[i] = obj_id
        obj_id += 1

    np.save(args.output, assignments)


if __name__ == "__main__":
    main()
