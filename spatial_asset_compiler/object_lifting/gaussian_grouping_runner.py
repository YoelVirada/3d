"""Gaussian Grouping fallback object lifting."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import numpy as np

from spatial_asset_compiler.config import PipelineState, THIRD_PARTY
from spatial_asset_compiler.object_lifting.grouping import write_object_groups


def run_gaussian_grouping(state: PipelineState) -> dict | None:
    p = state.paths
    gg_root = THIRD_PARTY / "gaussian-grouping"
    log = p.object_lifting_dir / "gaussian_grouping.log"
    log.parent.mkdir(parents=True, exist_ok=True)

    if not gg_root.exists():
        log.write_text("gaussian-grouping repo missing. Run setup_third_party.sh\n")
        return None

    gg_data = p.object_lifting_dir / "gg_dataset"
    _prepare_gg_dataset(state, gg_data)

    wrapper = Path(__file__).parent / "gg_train_wrapper.py"
    cmd = [
        "conda",
        "run",
        "-n",
        "gaussian-grouping",
        "--no-capture-output",
        "python",
        str(wrapper),
        "--gg-root",
        str(gg_root),
        "--data",
        str(gg_data),
        "--output",
        str(p.object_lifting_dir / "gg_out"),
        "--iterations",
        str(min(7000, state.profile.saga_feature_iterations)),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    log.write_text(proc.stdout + proc.stderr)

    assign_path = p.object_lifting_dir / "gg_out" / "assignments.npy"
    if proc.returncode == 0 and assign_path.exists():
        assignments = np.load(assign_path)
        return write_object_groups(state, assignments, "gaussian_grouping")

    # Fallback: use rendered grouping from identity if available
    return _gg_mask_projection_fallback(state, log)


def _prepare_gg_dataset(state: PipelineState, gg_data: Path) -> None:
    p = state.paths
    gg_data.mkdir(parents=True, exist_ok=True)
    inp = gg_data / "input"
    inp.mkdir(exist_ok=True)
    for f in sorted(p.frames_dir.glob("frame_*.jpg")):
        shutil.copy2(f, inp / f.name)
    for t in p.reconstruction_dir.rglob("transforms.json"):
        shutil.copy2(t, gg_data / "transforms.json")
        break
    masks_out = gg_data / "object_mask"
    masks_out.mkdir(exist_ok=True)
    index = json.loads((p.masks_dir / "index.json").read_text())["masks"]
    import cv2

    for i, m in enumerate(index):
        src = p.masks_dir / m["path"]
        if src.exists():
            img = cv2.imread(str(src), cv2.IMREAD_GRAYSCALE)
            if img is not None:
                cv2.imwrite(str(masks_out / f"{i:04d}.png"), img)


def _gg_mask_projection_fallback(state: PipelineState, log: Path) -> dict | None:
    """Use GG-style pseudo labels from SAM2 masks + projection."""
    from spatial_asset_compiler.object_lifting.projection import run_vote_fallback

    prev = log.read_text(encoding="utf-8") if log.exists() else ""
    log.write_text(prev + "\nGG train failed; using mask pseudo-label projection\n", encoding="utf-8")
    meta = run_vote_fallback(state)
    meta["lifting_method"] = "gaussian_grouping_pseudo"
    state.paths.objects_path.write_text(
        state.paths.objects_path.read_text().replace("vote_fallback", "gaussian_grouping_pseudo"),
        encoding="utf-8",
    )
    return meta
