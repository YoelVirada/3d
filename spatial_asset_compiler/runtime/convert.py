"""Convert scene.ply to runtime/mobile assets via @playcanvas/splat-transform."""

from __future__ import annotations

import json
import shutil
import time
from pathlib import Path
from typing import Any

from spatial_asset_compiler.config import REPO_ROOT, PipelineState
from spatial_asset_compiler.splats.io import count_gaussians_ply, file_size_mb
from spatial_asset_compiler.utils.subprocess_runner import CommandError, run_command

TOOLS_RUNTIME = REPO_ROOT / "tools" / "runtime"
PREVIEW_DECIMATE = "25%"
LOD_DECIMATES = ("50%", "25%", "10%")


def _find_splat_transform() -> list[str]:
    exe = shutil.which("splat-transform")
    if exe:
        return [exe]
    local = TOOLS_RUNTIME / "node_modules" / ".bin" / "splat-transform"
    if local.exists():
        return [str(local)]
    npx = shutil.which("npx")
    if npx and (TOOLS_RUNTIME / "package.json").exists():
        return [npx, "--prefix", str(TOOLS_RUNTIME), "splat-transform"]
    raise RuntimeError(
        "splat-transform not found. Install with: bash scripts/setup_runtime_tools.sh"
    )


def _tool_version(cli: list[str]) -> str | None:
    try:
        result = run_command(
            cli + ["--version"],
            check=False,
            timeout_s=30.0,
        )
        if result.returncode == 0:
            return (result.stdout or result.stderr).strip().splitlines()[0]
    except Exception:
        pass
    return None


def _rel(path: Path, base: Path) -> str:
    try:
        return str(path.relative_to(base))
    except ValueError:
        return str(path)


def _size_bytes(path: Path) -> int | None:
    return path.stat().st_size if path.exists() else None


def _run_convert(
    cli: list[str],
    *,
    input_ply: Path,
    output_path: Path,
    mid_args: list[str],
    trailing_args: list[str] | None = None,
    log_path: Path,
    env_note: str | None = None,
) -> dict[str, Any]:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [*cli, str(input_ply), *mid_args, str(output_path), *(trailing_args or [])]
    header = [f"# env: {env_note}"] if env_note else []
    t0 = time.perf_counter()
    try:
        result = run_command(
            cmd,
            log_path=log_path,
            log_header=header,
            hint="Install @playcanvas/splat-transform: bash scripts/setup_runtime_tools.sh",
        )
        return {
            "ok": True,
            "command": " ".join(cmd),
            "duration_s": round(result.duration_s, 3),
            "size_bytes": _size_bytes(output_path),
            "size_mb": round(file_size_mb(output_path), 4),
            "error": None,
        }
    except CommandError as exc:
        return {
            "ok": False,
            "command": " ".join(cmd),
            "duration_s": round(time.perf_counter() - t0, 3),
            "size_bytes": _size_bytes(output_path),
            "size_mb": round(file_size_mb(output_path), 4) if output_path.exists() else None,
            "error": str(exc),
        }


def _collect_lod_files(runtime_dir: Path) -> list[str]:
    files: list[str] = []
    for pattern in ("lod-meta.json", "lod-*.sog", "*.sog"):
        for path in sorted(runtime_dir.glob(pattern)):
            if path.is_file() and path.name != "scene.sog":
                files.append(path.name)
    return sorted(set(files))


def run_runtime_asset_conversion(state: PipelineState) -> dict[str, Any]:
    """Build runtime assets from scene.ply using splat-transform only."""
    p = state.paths
    scene_ply = p.scene_ply
    if not scene_ply.exists():
        raise FileNotFoundError(f"Missing input splat: {scene_ply}")

    runtime_dir = p.runtime_dir
    runtime_dir.mkdir(parents=True, exist_ok=True)
    logs_dir = p.logs_dir
    logs_dir.mkdir(parents=True, exist_ok=True)

    cli = _find_splat_transform()
    tool_version = _tool_version(cli)

    gaussian_count = 0
    try:
        gaussian_count = count_gaussians_ply(scene_ply)
    except Exception as exc:
        state.warnings.append(f"runtime_asset: gaussian count failed: {exc}")

    t0 = time.perf_counter()
    experiments: dict[str, Any] = {}
    errors: list[str] = []

    experiments["raw_ply"] = {
        "id": "raw_ply",
        "format": "ply",
        "description": "Raw PLY baseline (unchanged source)",
        "path": _rel(scene_ply, p.output_dir),
        "size_bytes": _size_bytes(scene_ply),
        "size_mb": round(file_size_mb(scene_ply), 4),
        "gaussian_count": gaussian_count,
        "command": None,
        "duration_s": 0.0,
        "ok": True,
        "error": None,
    }

    spz_path = runtime_dir / "scene.spz"
    spz = _run_convert(
        cli,
        input_ply=scene_ply,
        output_path=spz_path,
        mid_args=[],
        trailing_args=["--spz-version", "4"],
        log_path=logs_dir / "runtime_spz.log",
    )
    experiments["spz"] = {
        "id": "spz",
        "format": "spz",
        "description": "SPZ compressed baseline",
        "path": _rel(spz_path, p.output_dir),
        **spz,
    }
    if not spz["ok"]:
        errors.append(f"spz: {spz['error']}")

    sog_path = runtime_dir / "scene.sog"
    sog = _run_convert(
        cli,
        input_ply=scene_ply,
        output_path=sog_path,
        mid_args=[],
        log_path=logs_dir / "runtime_sog.log",
    )
    experiments["sog"] = {
        "id": "sog",
        "format": "sog",
        "description": "SOG compressed baseline",
        "path": _rel(sog_path, p.output_dir),
        **sog,
    }
    if not sog["ok"]:
        errors.append(f"sog: {sog['error']}")

    preview_path = runtime_dir / "preview.sog"
    preview = _run_convert(
        cli,
        input_ply=scene_ply,
        output_path=preview_path,
        mid_args=["--decimate", PREVIEW_DECIMATE],
        log_path=logs_dir / "runtime_preview.log",
    )
    experiments["preview"] = {
        "id": "preview",
        "format": "sog",
        "description": f"Preview SOG ({PREVIEW_DECIMATE} decimate)",
        "path": _rel(preview_path, p.output_dir),
        **preview,
    }
    if not preview["ok"]:
        errors.append(f"preview: {preview['error']}")

    lod_meta_path = runtime_dir / "lod-meta.json"
    lod = _build_lod_bundle(
        cli,
        scene_ply=scene_ply,
        runtime_dir=runtime_dir,
        lod_meta_path=lod_meta_path,
        logs_dir=logs_dir,
    )
    experiments["lod"] = {
        "id": "lod",
        "format": "lod-meta.json",
        "description": "LOD/SOG streaming baseline",
        "path": _rel(lod_meta_path, p.output_dir),
        "companion_files": _collect_lod_files(runtime_dir),
        **lod,
    }
    if not lod["ok"]:
        errors.append(f"lod: {lod['error']}")

    total_s = round(time.perf_counter() - t0, 3)
    runtime_assets = {
        "tool": "@playcanvas/splat-transform",
        "tool_version": tool_version,
        "source_ply": _rel(scene_ply, p.output_dir),
        "gaussian_count": gaussian_count,
        "total_conversion_time_s": total_s,
        "experiment_matrix": [
            "raw_ply",
            "spz",
            "sog",
            "lod",
        ],
        "experiments": experiments,
        "errors": errors,
        "outputs": {
            "spz": experiments["spz"]["path"] if spz["ok"] else None,
            "sog": experiments["sog"]["path"] if sog["ok"] else None,
            "preview": experiments["preview"]["path"] if preview["ok"] else None,
            "lod": experiments["lod"]["path"] if lod["ok"] else None,
        },
    }

    runtime_assets_path = runtime_dir / "runtime_assets.json"
    runtime_assets_path.write_text(
        json.dumps(runtime_assets, indent=2),
        encoding="utf-8",
    )
    runtime_assets["runtime_assets_path"] = _rel(runtime_assets_path, p.output_dir)

    state.benchmarks["runtime_asset"] = runtime_assets
    if errors:
        state.warnings.append("runtime_asset partial failures: " + "; ".join(errors))
    return runtime_assets


def _build_lod_bundle(
    cli: list[str],
    *,
    scene_ply: Path,
    runtime_dir: Path,
    lod_meta_path: Path,
    logs_dir: Path,
) -> dict[str, Any]:
    build_dir = runtime_dir / "_lod_build"
    build_dir.mkdir(parents=True, exist_ok=True)
    decimated: list[tuple[int, Path]] = [(0, scene_ply)]

    t0 = time.perf_counter()
    commands: list[str] = []
    try:
        for level, pct in enumerate(LOD_DECIMATES, start=1):
            out_ply = build_dir / f"lod{level}.ply"
            step = _run_convert(
                cli,
                input_ply=scene_ply,
                output_path=out_ply,
                mid_args=["--decimate", pct],
                log_path=logs_dir / f"runtime_lod_decimate_{level}.log",
            )
            commands.append(step["command"])
            if not step["ok"]:
                return {
                    "ok": False,
                    "command": " && ".join(commands),
                    "duration_s": round(time.perf_counter() - t0, 3),
                    "size_bytes": _size_bytes(lod_meta_path),
                    "size_mb": round(file_size_mb(lod_meta_path), 4)
                    if lod_meta_path.exists()
                    else None,
                    "error": step["error"],
                }
            decimated.append((level, out_ply))

        cmd: list[str] = [*cli]
        for level, path in decimated:
            cmd.extend([str(path), "-l", str(level)])
        cmd.extend([str(lod_meta_path), "--filter-nan"])
        commands.append(" ".join(cmd))

        result = run_command(
            cmd,
            log_path=logs_dir / "runtime_lod_bundle.log",
            hint="Install @playcanvas/splat-transform: bash scripts/setup_runtime_tools.sh",
        )
        ok = lod_meta_path.exists()
        return {
            "ok": ok,
            "command": " && ".join(commands),
            "duration_s": round(result.duration_s + (time.perf_counter() - t0), 3),
            "size_bytes": _size_bytes(lod_meta_path),
            "size_mb": round(file_size_mb(lod_meta_path), 4) if ok else None,
            "error": None if ok else "lod-meta.json was not created",
        }
    except CommandError as exc:
        return {
            "ok": False,
            "command": " && ".join(commands),
            "duration_s": round(time.perf_counter() - t0, 3),
            "size_bytes": _size_bytes(lod_meta_path),
            "size_mb": round(file_size_mb(lod_meta_path), 4)
            if lod_meta_path.exists()
            else None,
            "error": str(exc),
        }
