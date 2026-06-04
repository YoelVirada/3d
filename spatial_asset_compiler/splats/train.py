"""Splatfacto training via ns-train."""

from __future__ import annotations

import os
from pathlib import Path

from spatial_asset_compiler.config import PipelineState
from spatial_asset_compiler.utils.subprocess_runner import run_command


def _find_ns_train() -> str:
    import shutil

    exe = shutil.which("ns-train")
    if exe:
        return exe
    raise RuntimeError("ns-train not found. Run scripts/setup_env.sh")


def _data_dir_for_training(state: PipelineState) -> Path:
    rec = state.paths.reconstruction_dir
    for sub in ["ns_processed", ""]:
        base = rec / sub if sub else rec
        if (base / "transforms.json").exists():
            return base
    for t in rec.rglob("transforms.json"):
        return t.parent
    raise FileNotFoundError(f"No transforms.json under {rec}")


def train_splatfacto(state: PipelineState) -> dict:
    p = state.paths
    data_dir = _data_dir_for_training(state)
    max_iter = state.profile.splat_max_iterations
    downscale = state.profile.splat_downscale_factor

    cmd = [
        _find_ns_train(),
        "splatfacto",
        "--data",
        str(data_dir),
        "--max-num-iterations",
        str(max_iter),
        "--pipeline.datamanager.dataparser.downscale-factor",
        str(downscale),
        "--viewer.quit-on-train-completion",
        "True",
    ]
    log = p.logs_dir / "splat_train.log"
    env = os.environ.copy()
    env.setdefault("CUDA_VISIBLE_DEVICES", "0")

    result = run_command(
        cmd,
        log_path=log,
        env=env,
        hint="Install nerfstudio+gsplat: scripts/setup_env.sh",
        timeout_s=None,
    )

    # Find latest output config
    outputs_root = Path("outputs")
    config_yml = None
    if outputs_root.exists():
        configs = sorted(outputs_root.rglob("splatfacto/*/config.yml"), key=lambda x: x.stat().st_mtime)
        if configs:
            config_yml = configs[-1]

    meta = {
        "training_time_s": result.duration_s,
        "config_path": str(config_yml) if config_yml else None,
        "data_dir": str(data_dir),
        "max_iterations": max_iter,
    }
    state.benchmarks.setdefault("splats", {})
    state.benchmarks["splats"]["train"] = meta
    state.benchmarks["_splat_config"] = str(config_yml) if config_yml else None
    if not config_yml:
        state.warnings.append("splat_train: could not locate config.yml under outputs/")
    return meta
