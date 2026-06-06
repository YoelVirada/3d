"""Convert scene.ply to runtime/mobile assets via @playcanvas/splat-transform."""

from __future__ import annotations

import json
import shutil
import time
from pathlib import Path
from typing import Any, Callable

from spatial_asset_compiler.config import REPO_ROOT, PipelineState
from spatial_asset_compiler.splats.io import count_gaussians_ply, file_size_mb
from spatial_asset_compiler.utils.subprocess_runner import CommandError, run_command

TOOLS_RUNTIME = REPO_ROOT / "tools" / "runtime"
LOD_DECIMATES = ("50%", "25%", "10%")
VIEWER_SUPPORTED_PREVIEW_SUFFIXES = (".ply",)


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
        result = run_command(cli + ["--version"], check=False, timeout_s=30.0)
        if result.returncode == 0:
            return (result.stdout or result.stderr).strip().splitlines()[0]
    except Exception:
        pass
    return None


def _detect_capabilities(cli: list[str]) -> dict[str, bool]:
    try:
        result = run_command(cli + ["--help"], check=False, timeout_s=30.0)
        help_text = f"{result.stdout}\n{result.stderr}"
    except Exception:
        help_text = ""
    return {
        "spz_output": "SPZ Output Options" in help_text,
        "spz_version_flag": "--spz-version" in help_text,
        "sog_output": "SOG Output Options" in help_text or "Apply when writing `.sog`" in help_text,
        "lod_output": "LOD Output Options" in help_text or "lod-meta.json" in help_text,
    }


def _rel(path: Path, base: Path) -> str:
    try:
        return str(path.relative_to(base))
    except ValueError:
        return str(path)


def _size_bytes(path: Path) -> int | None:
    return path.stat().st_size if path.exists() else None


def _write_runtime_assets(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _run_convert(
    cli: list[str],
    *,
    input_ply: Path,
    output_path: Path,
    mid_args: list[str],
    trailing_args: list[str] | None = None,
    log_path: Path,
    timeout_s: float,
    progress: Callable[[str], None],
    step_name: str,
) -> dict[str, Any]:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [*cli, str(input_ply), *mid_args, str(output_path), *(trailing_args or [])]
    progress(f"{step_name}: start -> {output_path.name}")
    progress(f"{step_name}: cmd {' '.join(cmd)}")
    t0 = time.perf_counter()
    try:
        result = run_command(
            cmd,
            log_path=log_path,
            timeout_s=timeout_s,
            hint="Install @playcanvas/splat-transform: bash scripts/setup_runtime_tools.sh",
        )
        ok = output_path.exists() and output_path.stat().st_size > 0
        progress(
            f"{step_name}: done ok={ok} size={_size_bytes(output_path)} "
            f"duration={result.duration_s:.1f}s"
        )
        return {
            "ok": ok,
            "command": " ".join(cmd),
            "duration_s": round(result.duration_s, 3),
            "size_bytes": _size_bytes(output_path),
            "size_mb": round(file_size_mb(output_path), 4) if ok else None,
            "error": None if ok else "output file missing or empty",
            "skipped": False,
        }
    except CommandError as exc:
        progress(f"{step_name}: failed after {time.perf_counter() - t0:.1f}s")
        return {
            "ok": False,
            "command": " ".join(cmd),
            "duration_s": round(time.perf_counter() - t0, 3),
            "size_bytes": _size_bytes(output_path),
            "size_mb": round(file_size_mb(output_path), 4) if output_path.exists() else None,
            "error": str(exc),
            "skipped": False,
        }


def _skipped_step(*, reason: str, description: str, path: Path, base: Path) -> dict[str, Any]:
    return {
        "ok": False,
        "skipped": True,
        "description": description,
        "path": _rel(path, base),
        "command": None,
        "duration_s": 0.0,
        "size_bytes": None,
        "size_mb": None,
        "error": reason,
    }


def _collect_lod_files(runtime_dir: Path) -> list[str]:
    files: list[str] = []
    for pattern in ("lod-meta.json", "lod-*.sog", "*.sog"):
        for path in sorted(runtime_dir.glob(pattern)):
            if path.is_file() and path.name not in {"scene.sog", "preview.sog"}:
                files.append(path.name)
    return sorted(set(files))


def _stage_ok(experiments: dict[str, Any]) -> bool:
    preview = experiments.get("preview") or {}
    spz = experiments.get("spz") or {}
    return bool(preview.get("ok") or spz.get("ok"))


def run_runtime_asset_conversion(state: PipelineState) -> dict[str, Any]:
    """Build runtime assets from scene.ply using splat-transform only."""
    p = state.paths
    profile = state.profile
    scene_ply = p.scene_ply
    if not scene_ply.exists():
        raise FileNotFoundError(f"Missing input splat: {scene_ply}")

    runtime_dir = p.runtime_dir
    runtime_dir.mkdir(parents=True, exist_ok=True)
    logs_dir = p.logs_dir
    logs_dir.mkdir(parents=True, exist_ok=True)
    progress_log = logs_dir / "runtime_asset.log"
    progress_log.write_text("", encoding="utf-8")

    def progress(msg: str) -> None:
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        print(line)
        with open(progress_log, "a", encoding="utf-8") as f:
            f.write(line + "\n")

    runtime_assets_path = runtime_dir / "runtime_assets.json"
    experiments: dict[str, Any] = {}
    errors: list[str] = []
    t0 = time.perf_counter()
    runtime_assets: dict[str, Any] = {}

    try:
        cli = _find_splat_transform()
        tool_version = _tool_version(cli)
        caps = _detect_capabilities(cli)
        timeout_s = profile.runtime_conversion_timeout_s
        progress(
            f"runtime_asset: tool={tool_version} caps={caps} timeout_s={timeout_s} "
            f"full_sog={profile.runtime_enable_full_sog} lod={profile.runtime_enable_lod}"
        )

        gaussian_count = 0
        try:
            gaussian_count = count_gaussians_ply(scene_ply)
        except Exception as exc:
            state.warnings.append(f"runtime_asset: gaussian count failed: {exc}")

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
            "skipped": False,
            "error": None,
        }
        _write_runtime_assets(
            runtime_assets_path,
            {"status": "in_progress", "experiments": experiments},
        )

        preview_path = runtime_dir / "preview.ply"
        preview = _run_convert(
            cli,
            input_ply=scene_ply,
            output_path=preview_path,
            mid_args=["--decimate", profile.runtime_preview_decimate],
            log_path=logs_dir / "runtime_preview.log",
            timeout_s=timeout_s,
            progress=progress,
            step_name="preview",
        )
        experiments["preview"] = {
            "id": "preview",
            "format": "ply",
            "description": f"Preview PLY ({profile.runtime_preview_decimate} decimate)",
            "path": _rel(preview_path, p.output_dir),
            **preview,
        }
        if not preview["ok"] and not preview.get("skipped"):
            errors.append(f"preview: {preview['error']}")
        _write_runtime_assets(
            runtime_assets_path,
            {"status": "in_progress", "experiments": experiments, "errors": errors},
        )

        spz_path = runtime_dir / "scene.spz"
        if caps["spz_output"]:
            trailing = ["--spz-version", "4"] if caps["spz_version_flag"] else []
            spz = _run_convert(
                cli,
                input_ply=scene_ply,
                output_path=spz_path,
                mid_args=[],
                trailing_args=trailing,
                log_path=logs_dir / "runtime_spz.log",
                timeout_s=timeout_s,
                progress=progress,
                step_name="spz",
            )
        else:
            spz = _skipped_step(
                reason="splat-transform help does not advertise .spz output",
                description="SPZ compressed baseline",
                path=spz_path,
                base=p.output_dir,
            )
            spz["id"] = "spz"
            spz["format"] = "spz"
            progress("spz: skipped (unsupported by installed splat-transform)")
        experiments["spz"] = {"id": "spz", "format": "spz", "description": "SPZ compressed baseline", "path": _rel(spz_path, p.output_dir), **spz}
        if not spz["ok"] and not spz.get("skipped"):
            errors.append(f"spz: {spz['error']}")
        _write_runtime_assets(
            runtime_assets_path,
            {"status": "in_progress", "experiments": experiments, "errors": errors},
        )

        sog_path = runtime_dir / "scene.sog"
        if profile.runtime_enable_full_sog and caps["sog_output"]:
            sog = _run_convert(
                cli,
                input_ply=scene_ply,
                output_path=sog_path,
                mid_args=[],
                log_path=logs_dir / "runtime_sog.log",
                timeout_s=timeout_s,
                progress=progress,
                step_name="sog",
            )
        else:
            reason = "disabled for profile (set runtime_enable_full_sog=True to opt in)"
            if not profile.runtime_enable_full_sog:
                progress(f"sog: skipped ({reason})")
            else:
                reason = "splat-transform help does not advertise .sog output"
                progress(f"sog: skipped ({reason})")
            sog = _skipped_step(
                reason=reason,
                description="SOG compressed baseline",
                path=sog_path,
                base=p.output_dir,
            )
            sog["id"] = "sog"
            sog["format"] = "sog"
        experiments["sog"] = {"id": "sog", "format": "sog", "description": "SOG compressed baseline", "path": _rel(sog_path, p.output_dir), **sog}
        if not sog["ok"] and not sog.get("skipped"):
            errors.append(f"sog: {sog['error']}")
        _write_runtime_assets(
            runtime_assets_path,
            {"status": "in_progress", "experiments": experiments, "errors": errors},
        )

        lod_meta_path = runtime_dir / "lod-meta.json"
        if profile.runtime_enable_lod and caps["lod_output"]:
            lod = _build_lod_bundle(
                cli,
                scene_ply=scene_ply,
                runtime_dir=runtime_dir,
                lod_meta_path=lod_meta_path,
                logs_dir=logs_dir,
                timeout_s=timeout_s,
                progress=progress,
            )
        else:
            reason = "disabled for profile (set runtime_enable_lod=True to opt in)"
            if not profile.runtime_enable_lod:
                progress(f"lod: skipped ({reason})")
            else:
                reason = "splat-transform help does not advertise lod-meta.json output"
                progress(f"lod: skipped ({reason})")
            lod = _skipped_step(
                reason=reason,
                description="LOD/SOG streaming baseline",
                path=lod_meta_path,
                base=p.output_dir,
            )
            lod["companion_files"] = []
        experiments["lod"] = {
            "id": "lod",
            "format": "lod-meta.json",
            "description": "LOD/SOG streaming baseline",
            "path": _rel(lod_meta_path, p.output_dir),
            "companion_files": lod.get("companion_files", _collect_lod_files(runtime_dir)),
            **lod,
        }
        if not lod["ok"] and not lod.get("skipped"):
            errors.append(f"lod: {lod['error']}")

        matrix = ["raw_ply", "preview", "spz"]
        if profile.runtime_enable_full_sog:
            matrix.append("sog")
        if profile.runtime_enable_lod:
            matrix.append("lod")

        runtime_assets = {
            "tool": "@playcanvas/splat-transform",
            "tool_version": tool_version,
            "capabilities": caps,
            "profile": profile.name,
            "source_ply": _rel(scene_ply, p.output_dir),
            "gaussian_count": gaussian_count,
            "total_conversion_time_s": round(time.perf_counter() - t0, 3),
            "experiment_matrix": matrix,
            "experiments": experiments,
            "errors": errors,
            "stage_ok": _stage_ok(experiments),
            "outputs": {
                "preview": experiments["preview"]["path"] if experiments["preview"]["ok"] else None,
                "spz": experiments["spz"]["path"] if experiments["spz"]["ok"] else None,
                "sog": experiments["sog"]["path"] if experiments["sog"]["ok"] else None,
                "lod": experiments["lod"]["path"] if experiments["lod"]["ok"] else None,
            },
            "viewer_supported_preview": None,
            "status": "ok" if _stage_ok(experiments) else "partial",
        }
        preview_out = runtime_assets["outputs"]["preview"]
        if preview_out and preview_out.endswith(".ply"):
            runtime_assets["viewer_supported_preview"] = preview_out

    except Exception as exc:
        progress(f"runtime_asset: fatal error: {exc}")
        errors.append(str(exc))
        runtime_assets = {
            "tool": "@playcanvas/splat-transform",
            "status": "failed",
            "experiments": experiments,
            "errors": errors,
            "stage_ok": _stage_ok(experiments),
            "total_conversion_time_s": round(time.perf_counter() - t0, 3),
        }
        state.warnings.append(f"runtime_asset error: {exc}")

    runtime_assets["runtime_assets_path"] = _rel(runtime_assets_path, p.output_dir)
    _write_runtime_assets(runtime_assets_path, runtime_assets)
    state.benchmarks["runtime_asset"] = runtime_assets

    if runtime_assets.get("stage_ok"):
        progress("runtime_asset: stage_ok (preview and/or spz produced)")
    else:
        msg = "runtime_asset partial failure: no preview or spz produced"
        progress(msg)
        state.warnings.append(msg + (f" ({'; '.join(errors)})" if errors else ""))

    return runtime_assets


def _build_lod_bundle(
    cli: list[str],
    *,
    scene_ply: Path,
    runtime_dir: Path,
    lod_meta_path: Path,
    logs_dir: Path,
    timeout_s: float,
    progress: Callable[[str], None],
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
                timeout_s=timeout_s,
                progress=progress,
                step_name=f"lod_decimate_{level}",
            )
            if step.get("command"):
                commands.append(step["command"])
            if not step["ok"]:
                return {
                    "ok": False,
                    "skipped": False,
                    "command": " && ".join(commands),
                    "duration_s": round(time.perf_counter() - t0, 3),
                    "size_bytes": _size_bytes(lod_meta_path),
                    "size_mb": round(file_size_mb(lod_meta_path), 4)
                    if lod_meta_path.exists()
                    else None,
                    "error": step["error"],
                    "companion_files": _collect_lod_files(runtime_dir),
                }
            decimated.append((level, out_ply))

        cmd: list[str] = [*cli]
        for level, path in decimated:
            cmd.extend([str(path), "-l", str(level)])
        cmd.extend([str(lod_meta_path), "--filter-nan"])
        commands.append(" ".join(cmd))
        progress(f"lod_bundle: start -> {lod_meta_path.name}")
        progress(f"lod_bundle: cmd {' '.join(cmd)}")

        result = run_command(
            cmd,
            log_path=logs_dir / "runtime_lod_bundle.log",
            timeout_s=timeout_s,
            hint="Install @playcanvas/splat-transform: bash scripts/setup_runtime_tools.sh",
        )
        ok = lod_meta_path.exists()
        progress(f"lod_bundle: done ok={ok} duration={result.duration_s:.1f}s")
        return {
            "ok": ok,
            "skipped": False,
            "command": " && ".join(commands),
            "duration_s": round(result.duration_s + (time.perf_counter() - t0), 3),
            "size_bytes": _size_bytes(lod_meta_path),
            "size_mb": round(file_size_mb(lod_meta_path), 4) if ok else None,
            "error": None if ok else "lod-meta.json was not created",
            "companion_files": _collect_lod_files(runtime_dir),
        }
    except CommandError as exc:
        progress(f"lod_bundle: failed after {time.perf_counter() - t0:.1f}s")
        return {
            "ok": False,
            "skipped": False,
            "command": " && ".join(commands),
            "duration_s": round(time.perf_counter() - t0, 3),
            "size_bytes": _size_bytes(lod_meta_path),
            "size_mb": round(file_size_mb(lod_meta_path), 4)
            if lod_meta_path.exists()
            else None,
            "error": str(exc),
            "companion_files": _collect_lod_files(runtime_dir),
        }
