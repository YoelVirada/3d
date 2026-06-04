"""SAGA (Segment Any 3D Gaussians) object lifting via subprocess."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import numpy as np

from spatial_asset_compiler.config import PipelineState, THIRD_PARTY
from spatial_asset_compiler.object_lifting.grouping import write_object_groups
from spatial_asset_compiler.splats.io import load_splat_positions


def _conda_run(env_name: str, script: Path, args: list[str], log: Path) -> int:
    cmd = [
        "conda",
        "run",
        "-n",
        env_name,
        "--no-capture-output",
        "python",
        str(script),
        *args,
    ]
    log.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    with open(log, "w", encoding="utf-8") as f:
        f.write(f"# {' '.join(cmd)}\n# exit {proc.returncode}\n")
        f.write(proc.stdout)
        f.write(proc.stderr)
    return proc.returncode


def _prepare_saga_dataset(state: PipelineState, saga_data: Path) -> None:
    """Copy reconstruction + frames into SAGA-friendly layout."""
    p = state.paths
    saga_data.mkdir(parents=True, exist_ok=True)
    images = saga_data / "images"
    images.mkdir(exist_ok=True)
    for f in sorted(p.frames_dir.glob("frame_*.jpg")):
        dest = images / f.name
        if not dest.exists():
            try:
                dest.symlink_to(f.resolve())
            except OSError:
                shutil.copy2(f, dest)
    # transforms
    for t in p.reconstruction_dir.rglob("transforms.json"):
        shutil.copy2(t, saga_data / "transforms.json")
        break
    # masks for prompts
    prompts = saga_data / "sam2_prompts.json"
    index_path = p.masks_dir / "index.json"
    if index_path.exists():
        shutil.copy2(index_path, prompts)


def _saga_assign_from_masks(state: PipelineState) -> np.ndarray | None:
    """
    When full SAGA training is unavailable, use SAM2 mask prompts + splat projection
    in saga-lift env via bundled helper — still tagged saga_prompt if subprocess succeeds.
    """
    helper = Path(__file__).parent / "saga_mask_assign.py"
    if not helper.exists():
        return None
    out_npy = state.paths.object_lifting_dir / "saga_assignments.npy"
    rc = _conda_run(
        "saga-lift",
        helper,
        [
            "--ply",
            str(state.paths.scene_ply),
            "--transforms",
            str(_find_transforms(state.paths.reconstruction_dir)),
            "--masks-index",
            str(state.paths.masks_dir / "index.json"),
            "--masks-dir",
            str(state.paths.masks_dir),
            "--output",
            str(out_npy),
        ],
        state.paths.object_lifting_dir / "saga.log",
    )
    if rc != 0 or not out_npy.exists():
        return None
    return np.load(out_npy)


def _find_transforms(rec_dir: Path) -> Path:
    for t in [rec_dir / "transforms.json", *rec_dir.rglob("transforms.json")]:
        if t.exists():
            return t
    raise FileNotFoundError("transforms.json not found")


def run_saga(state: PipelineState) -> dict | None:
    p = state.paths
    p.object_lifting_dir.mkdir(parents=True, exist_ok=True)
    saga_root = THIRD_PARTY / "SegAnyGAussians"
    log = p.object_lifting_dir / "saga.log"

    if not saga_root.exists():
        with open(log, "w") as f:
            f.write("SAGA repo missing. Run scripts/setup_third_party.sh\n")
        return None

    saga_data = p.object_lifting_dir / "saga_dataset"
    _prepare_saga_dataset(state, saga_data)

    # Try full pipeline script if present
    train_script = saga_root / "train_scene.py"
    if train_script.exists():
        rc = _conda_run(
            "saga-lift",
            Path(__file__).parent / "saga_pipeline_wrapper.py",
            [
                "--saga-root",
                str(saga_root),
                "--data",
                str(saga_data),
                "--output",
                str(p.object_lifting_dir / "saga_out"),
                "--iterations",
                str(state.profile.saga_feature_iterations),
            ],
            log,
        )
        out_assign = p.object_lifting_dir / "saga_out" / "assignments.npy"
        if rc == 0 and out_assign.exists():
            assignments = np.load(out_assign)
            return write_object_groups(state, assignments, "saga")

    # Prompt-based assignment using SAM2 masks (research-guided, not pure vote)
    assignments = _saga_assign_from_masks(state)
    if assignments is not None:
        meta = write_object_groups(state, assignments, "saga_prompt")
        meta["note"] = "SAGA full train skipped; SAM2 prompt assignment in saga-lift env"
        return meta

    return None
