"""Export Gaussian splat to scene.ply."""

from __future__ import annotations

import os
import shutil
from pathlib import Path

from spatial_asset_compiler.config import PipelineState
from spatial_asset_compiler.splats.io import count_gaussians_ply, file_size_mb
from spatial_asset_compiler.utils.subprocess_runner import run_command

_TORCH_EXPORT_ENV = "TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD"


def _find_ns_export() -> str:
    import shutil

    exe = shutil.which("ns-export")
    if exe:
        return exe
    raise RuntimeError("ns-export not found. Run scripts/setup_env.sh")


def _resolve_config(state: PipelineState) -> Path:
    cfg = state.benchmarks.get("_splat_config")
    if cfg and Path(cfg).exists():
        return Path(cfg)
    outputs_root = Path("outputs")
    configs = sorted(
        outputs_root.rglob("splatfacto/*/config.yml"),
        key=lambda x: x.stat().st_mtime,
    )
    if not configs:
        raise FileNotFoundError(
            "No splatfacto config.yml. Run splat training first."
        )
    return configs[-1]


def export_gaussian_splat(state: PipelineState) -> dict:
    p = state.paths
    config_yml = _resolve_config(state)
    export_dir = p.splats_dir
    export_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        _find_ns_export(),
        "gaussian-splat",
        "--load-config",
        str(config_yml.resolve()),
        "--output-dir",
        str(export_dir.resolve()),
    ]
    log = p.logs_dir / "splat_export.log"
    env = os.environ.copy()
    env[_TORCH_EXPORT_ENV] = "1"
    result = run_command(
        cmd,
        log_path=log,
        env=env,
        log_header=[f"# env: {_TORCH_EXPORT_ENV}=1"],
        hint="Check ns-export and checkpoint exist",
    )

    ply_files = list(export_dir.rglob("*.ply"))
    if not ply_files:
        raise FileNotFoundError(f"No PLY exported to {export_dir}. See {log}")

    src = max(ply_files, key=lambda x: x.stat().st_size)
    shutil.copy2(src, p.scene_ply)

    n_gaussians = 0
    try:
        n_gaussians = count_gaussians_ply(p.scene_ply)
    except Exception as e:
        state.warnings.append(f"ply_parse: {e}")

    meta = {
        "export_time_s": result.duration_s,
        "config_path": str(config_yml),
        "gaussian_count": n_gaussians,
        "raw_size_mb": file_size_mb(p.scene_ply),
        "scene_ply": str(p.scene_ply),
    }
    state.benchmarks.setdefault("splats", {})
    state.benchmarks["splats"]["export"] = meta
    return meta
