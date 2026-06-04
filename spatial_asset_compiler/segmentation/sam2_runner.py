"""SAM2 automatic mask generation on keyframes."""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import cv2
import numpy as np

from spatial_asset_compiler.config import PipelineState, THIRD_PARTY
from spatial_asset_compiler.segmentation.masks import write_mask_index


def run_sam2_segmentation(state: PipelineState) -> dict:
    p = state.paths
    frames = sorted(p.frames_dir.glob("frame_*.jpg"))
    if not frames:
        raise FileNotFoundError(f"No frames in {p.frames_dir}")

    stride = state.profile.sam2_keyframe_stride
    keyframes = frames[:: max(1, stride)]
    masks_dir = p.masks_dir
    masks_dir.mkdir(parents=True, exist_ok=True)

    sam2_root = THIRD_PARTY / "sam2"
    if not sam2_root.exists():
        raise RuntimeError(
            f"SAM2 not found at {sam2_root}. Run: scripts/setup_third_party.sh"
        )

    # Ensure sam2 on path
    if str(sam2_root) not in sys.path:
        sys.path.insert(0, str(sam2_root))

    start = time.perf_counter()
    entries: list[dict] = []
    mask_count = 0
    model_id = state.profile.sam2_model

    import torch

    ckpt_dir = THIRD_PARTY / "checkpoints" / "sam2"
    cfg_ckpt = {
        "sam2.1_hiera_small": (
            "configs/sam2.1/sam2.1_hiera_s.yaml",
            "sam2.1_hiera_small.pt",
        ),
        "sam2.1_hiera_base": (
            "configs/sam2.1/sam2.1_hiera_b+.yaml",
            "sam2.1_hiera_base_plus.pt",
        ),
        "sam2.1_hiera_large": (
            "configs/sam2.1/sam2.1_hiera_l.yaml",
            "sam2.1_hiera_large.pt",
        ),
    }
    cfg_rel, ckpt_name = cfg_ckpt.get(model_id, cfg_ckpt["sam2.1_hiera_small"])
    ckpt_path = ckpt_dir / ckpt_name
    if not ckpt_path.exists():
        raise FileNotFoundError(
            f"SAM2 checkpoint missing: {ckpt_path}\n"
            "Run: scripts/download_sam2_checkpoints.sh"
        )

    prev_cwd = os.getcwd()
    os.chdir(sam2_root)
    try:
        from sam2.build_sam import build_sam2
        from sam2.automatic_mask_generator import SAM2AutomaticMaskGenerator

        device = "cuda" if torch.cuda.is_available() else "cpu"
        sam2_model = build_sam2(
            config_file=cfg_rel,
            ckpt_path=str(ckpt_path),
            device=device,
        )
        generator = SAM2AutomaticMaskGenerator(
            sam2_model,
            points_per_side=12,
            pred_iou_thresh=0.7,
            stability_score_thresh=0.85,
        )

        for frame_path in keyframes:
            image = cv2.imread(str(frame_path))
            if image is None:
                continue
            image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            with torch.inference_mode():
                if device == "cuda":
                    with torch.autocast("cuda", dtype=torch.bfloat16):
                        masks = generator.generate(image_rgb)
                else:
                    masks = generator.generate(image_rgb)

            for i, m in enumerate(masks[:15]):
                seg = m.get("segmentation")
                if seg is None:
                    continue
                mask_id = f"{frame_path.stem}_mask_{i:03d}"
                out_png = masks_dir / f"{mask_id}.png"
                cv2.imwrite(str(out_png), (seg.astype(np.uint8) * 255))
                ys, xs = np.where(seg)
                if len(xs) == 0:
                    continue
                bbox = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
                entries.append(
                    {
                        "mask_id": mask_id,
                        "frame": frame_path.name,
                        "path": out_png.name,
                        "area": int(seg.sum()),
                        "bbox": bbox,
                    }
                )
                mask_count += 1
    finally:
        os.chdir(prev_cwd)

    write_mask_index(masks_dir, entries)
    duration = time.perf_counter() - start
    meta = {
        "model": model_id,
        "keyframes_processed": len(keyframes),
        "mask_count": mask_count,
        "segmentation_time_s": duration,
    }
    state.benchmarks.setdefault("segmentation", {})
    state.benchmarks["segmentation"].update(meta)
    return meta
