"""Pipeline execution with optional run telemetry."""

from __future__ import annotations

import time
from contextlib import nullcontext
from pathlib import Path

from spatial_asset_compiler.asset.package import finalize_package
from spatial_asset_compiler.benchmarks.timer import StageTimer
from spatial_asset_compiler.config import PipelineState
from spatial_asset_compiler.ingest.video import extract_frames
from spatial_asset_compiler.mesh.mesh_runner import run_mesh_extraction
from spatial_asset_compiler.object_lifting.lift import run_object_lifting
from spatial_asset_compiler.reconstruction.nerfstudio_runner import run_reconstruction
from spatial_asset_compiler.runs.tracker import RunTracker, StageRecorder
from spatial_asset_compiler.segmentation.sam2_runner import run_sam2_segmentation
from spatial_asset_compiler.splats.export import export_gaussian_splat
from spatial_asset_compiler.splats.train import train_splatfacto
from spatial_asset_compiler.viewer.export_viewer_assets import export_viewer_assets

STAGES = [
    "ingest",
    "reconstruction",
    "splats",
    "segmentation",
    "object_lifting",
    "mesh",
    "package",
]


def execute_pipeline(
    state: PipelineState,
    stages: list[str],
    *,
    tracker: RunTracker | None = None,
    pipeline_log: Path | None = None,
) -> int:
    """Run pipeline stages. Returns 0 on success, 1 on failure."""
    paths = state.paths
    timer = StageTimer()
    pipeline_log = pipeline_log or (Path("logs") / "pipeline" / f"{paths.scene_id}.log")
    pipeline_log.parent.mkdir(parents=True, exist_ok=True)

    def log(msg: str) -> None:
        line = f"[{time.strftime('%H:%M:%S')}] {msg}\n"
        with open(pipeline_log, "a", encoding="utf-8") as f:
            f.write(line)
        print(msg)
        if tracker:
            tracker.copy_stage_log(pipeline_log, dest_name=f"pipeline_{paths.scene_id}.log")

    def stg(name: str, **kwargs):
        if tracker:
            return tracker.stage(name, **kwargs)
        return nullcontext(StageRecorder(inputs=[], outputs=[], extra={}, tool=None))

    log(f"Pipeline start scene_id={paths.scene_id} profile={state.profile.name}")

    try:
        if "ingest" in stages:
            videos = list(paths.capture_dir.glob("video.*"))
            with stg(
                "ingest",
                tool="ffmpeg",
                inputs=videos,
            ) as rec:
                t0 = time.perf_counter()
                meta = extract_frames(state)
                state.benchmarks.setdefault("ingest", {})["extraction_time_s"] = (
                    time.perf_counter() - t0
                )
                rec.add_output(paths.frames_dir)
                rec.extra["frame_count"] = meta.get("frame_count")
            log("ingest: ok")
        elif tracker:
            tracker.record_skipped("ingest")

        if "reconstruction" in stages:
            with stg("reconstruction", tool="nerfstudio / COLMAP") as rec:
                run_reconstruction(state)
                rec.add_output(paths.reconstruction_dir)
            log("reconstruction: ok")
        elif tracker:
            tracker.record_skipped("reconstruction")

        if "splats" in stages:
            with stg("splats_train", tool="splatfacto"):
                train_splatfacto(state)
            with stg("splats_export", tool="splatfacto export") as rec:
                export_gaussian_splat(state)
                if paths.scene_ply.exists():
                    rec.add_output(paths.scene_ply)
            if not paths.scene_ply.exists():
                raise RuntimeError("Hard gate failed: scene.ply not produced")
            log("splats: ok")
        elif tracker:
            tracker.record_skipped("splats_train")
            tracker.record_skipped("splats_export")

        if "segmentation" in stages:
            with stg("segmentation", tool="SAM2") as rec:
                run_sam2_segmentation(state)
                rec.add_output(paths.masks_dir)
            log("segmentation: ok")
        elif tracker:
            tracker.record_skipped("segmentation")

        if "object_lifting" in stages:
            with stg("object_lifting", tool="SAGA / Gaussian Grouping") as rec:
                run_object_lifting(state)
                rec.tool = str(state.benchmarks.get("object_lifting_method", "unknown"))
                rec.add_output(paths.object_groups_dir)
            log(f"object_lifting: {state.benchmarks.get('object_lifting_method')}")
        elif tracker:
            tracker.record_skipped("object_lifting")

        if "mesh" in stages:
            with stg("mesh", tool="Open3D / SuGaR") as rec:
                run_mesh_extraction(state)
                rec.add_output(paths.meshes_dir)
            log("mesh: ok")
        elif tracker:
            tracker.record_skipped("mesh")

        if "package" in stages:
            state.benchmarks["stage_timings_s"] = timer.as_dict()
            with stg("package", tool="spatial_asset_compiler") as rec:
                finalize_package(state)
                rec.add_output(
                    paths.manifest_path,
                    paths.objects_path,
                    paths.benchmarks_path,
                )
            with stg("viewer_export", tool="viewer export") as rec:
                export_viewer_assets(state)
                rec.add_output(paths.viewer_dir)
            log(f"package: {paths.manifest_path}")
        elif tracker:
            tracker.record_skipped("package")
            tracker.record_skipped("viewer_export")

    except Exception as e:
        log(f"FAILED: {e}")
        state.failures.append(str(e))
        if tracker:
            tracker.complete(success=False, failure_reason=str(e))
        try:
            finalize_package(state)
        except Exception:
            pass
        return 1

    if state.warnings:
        log("warnings: " + "; ".join(state.warnings))
    log("Pipeline complete.")
    if tracker:
        tracker.complete(success=True)
    return 0
