"""FastAPI capture server: upload, pipeline runner, run status, mobile metrics."""

from __future__ import annotations

import json
import os
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles
import uvicorn

from spatial_asset_compiler.config import (
    DATA_CAPTURES,
    DEFAULT_EXPORTS,
    PROFILES,
    REPO_ROOT,
    PipelinePaths,
    PipelineState,
)
from spatial_asset_compiler.pipeline import STAGES, execute_pipeline
from spatial_asset_compiler.runs.schemas import MobileMetricsPayload, RunResultResponse, RunStatusResponse
from spatial_asset_compiler.runs.tracker import RunTracker

app = FastAPI(title="Spatial Capture Server", version="0.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory handles for active runs (also persisted under runs/{scene_id}/)
_active: dict[str, RunTracker] = {}


def _public_base(request: Request) -> str:
    return os.environ.get("SAC_PUBLIC_BASE_URL", str(request.base_url)).rstrip("/")


def _viewer_base(request: Request) -> str:
    return os.environ.get("SAC_VIEWER_BASE_URL", "http://127.0.0.1:5173").rstrip("/")


def _get_tracker(run_id: str) -> RunTracker:
    if run_id in _active:
        return _active[run_id]
    scene_id = RunTracker.resolve_scene_id(run_id)
    if not scene_id:
        raise HTTPException(404, f"Unknown run_id: {run_id}")
    loaded = RunTracker.load_existing(scene_id)
    if not loaded or loaded.run_id != run_id:
        raise HTTPException(404, f"Run not found: {run_id}")
    return loaded


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "repo": str(REPO_ROOT)}


async def _save_capture(
    scene_id: str,
    video: UploadFile,
    metadata: str,
) -> tuple[Path, Path, int]:
    dest = DATA_CAPTURES / scene_id
    dest.mkdir(parents=True, exist_ok=True)
    ext = Path(video.filename or "video.mp4").suffix or ".mp4"
    video_path = dest / f"video{ext}"
    content = await video.read()
    video_path.write_bytes(content)
    try:
        meta = json.loads(metadata)
    except json.JSONDecodeError:
        meta = {"raw": metadata}
    cap_json = dest / "capture.json"
    cap_json.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return video_path, cap_json, len(content)


def _run_pipeline_thread(
    tracker: RunTracker,
    profile_name: str,
) -> None:
    paths = PipelinePaths(
        scene_id=tracker.scene_id,
        capture_dir=(DATA_CAPTURES / tracker.scene_id).resolve(),
        output_dir=(DEFAULT_EXPORTS / tracker.scene_id).resolve(),
    )
    paths.output_dir.mkdir(parents=True, exist_ok=True)
    paths.logs_dir.mkdir(parents=True, exist_ok=True)
    profile = PROFILES.get(profile_name, PROFILES["dev"])
    state = PipelineState(paths=paths, profile=profile)
    log_path = tracker.stage_logs_dir / f"pipeline_{tracker.scene_id}.log"
    rc = execute_pipeline(state, list(STAGES), tracker=tracker, pipeline_log=log_path)
    if rc != 0 and tracker._status != "failed":
        tracker.complete(success=False, failure_reason="pipeline exited with error")


@app.post("/captures/{scene_id}")
async def upload_capture_path(
    scene_id: str,
    request: Request,
    video: UploadFile = File(...),
    metadata: str = Form("{}"),
    profile: str = Form("dev"),
    start_pipeline: bool = Form(True),
) -> JSONResponse:
    return await _upload_and_maybe_run(
        scene_id, request, video, metadata, profile, start_pipeline
    )


@app.post("/captures")
async def upload_capture(
    request: Request,
    scene_id: str = Form(...),
    video: UploadFile = File(...),
    metadata: str = Form("{}"),
    profile: str = Form("dev"),
    start_pipeline: bool = Form(True),
) -> JSONResponse:
    return await _upload_and_maybe_run(
        scene_id, request, video, metadata, profile, start_pipeline
    )


async def _upload_and_maybe_run(
    scene_id: str,
    request: Request,
    video: UploadFile,
    metadata: str,
    profile: str,
    start_pipeline: bool,
) -> JSONResponse:
    t0 = time.perf_counter()
    tracker = RunTracker.for_scene(scene_id, profile=profile)
    _active[tracker.run_id] = tracker

    video_path, cap_json, nbytes = await _save_capture(scene_id, video, metadata)
    upload_sec = time.perf_counter() - t0

    with tracker.stage(
        "upload_receive",
        tool="capture_server",
        inputs=[],
        outputs=[video_path, cap_json],
        extra={"upload_duration_sec": round(upload_sec, 3)},
    ):
        pass

    if start_pipeline:
        tracker.set_status("running")
        thread = threading.Thread(
            target=_run_pipeline_thread,
            args=(tracker, profile),
            daemon=True,
        )
        thread.start()
        status = "running"
    else:
        tracker.complete(success=True)
        status = "completed"

    base = _public_base(request)
    return JSONResponse(
        {
            "scene_id": scene_id,
            "run_id": tracker.run_id,
            "status": status,
            "video": str(video_path.relative_to(REPO_ROOT)),
            "capture_json": str(cap_json.relative_to(REPO_ROOT)),
            "bytes": nbytes,
            "upload_duration_sec": round(upload_sec, 3),
            "status_url": f"{base}/runs/{tracker.run_id}/status",
            "result_url": f"{base}/runs/{tracker.run_id}/result",
        }
    )


@app.get("/runs/{run_id}/status", response_model=RunStatusResponse)
def run_status(run_id: str) -> RunStatusResponse:
    tracker = _get_tracker(run_id)
    d = tracker.status_dict()
    return RunStatusResponse(**d)


@app.get("/runs/{run_id}/result", response_model=RunResultResponse)
def run_result(run_id: str, request: Request) -> RunResultResponse:
    tracker = _get_tracker(run_id)
    d = tracker.status_dict()
    status = d["status"]
    if status not in ("completed", "failed"):
        raise HTTPException(409, "Run still in progress")

    base = _public_base(request)
    viewer_base = _viewer_base(request)
    manifest_path = DEFAULT_EXPORTS / tracker.scene_id / "manifest.json"
    manifest_url = None
    viewer_url = None
    if manifest_path.exists():
        rel = f"/exports/{tracker.scene_id}/manifest.json"
        manifest_url = f"{base}{rel}"
        pkg = quote(manifest_url, safe="")
        viewer_url = (
            f"{viewer_base}/?package={pkg}"
            f"&run_id={tracker.run_id}"
            f"&api={quote(base, safe='')}"
        )

    return RunResultResponse(
        run_id=tracker.run_id,
        scene_id=tracker.scene_id,
        status=status,  # type: ignore[arg-type]
        manifest_url=manifest_url,
        manifest_path=str(manifest_path.relative_to(REPO_ROOT)) if manifest_path.exists() else None,
        viewer_url=viewer_url,
        report_url=f"{base}/runs/{run_id}/report",
        report_md_url=f"{base}/runs/{run_id}/report.md",
        failure_reason=d.get("failure_reason"),
    )


@app.get("/runs/{run_id}/report")
def run_report_json(run_id: str) -> FileResponse:
    tracker = _get_tracker(run_id)
    if not tracker.report_json_path.exists():
        raise HTTPException(404, "Report not ready")
    return FileResponse(tracker.report_json_path, media_type="application/json")


@app.get("/runs/{run_id}/report.md")
def run_report_md(run_id: str) -> PlainTextResponse:
    tracker = _get_tracker(run_id)
    if not tracker.report_md_path.exists():
        raise HTTPException(404, "Report not ready")
    return PlainTextResponse(tracker.report_md_path.read_text(encoding="utf-8"))


@app.post("/runs/{run_id}/mobile-metrics")
async def mobile_metrics(run_id: str, request: Request) -> JSONResponse:
    tracker = _get_tracker(run_id)
    body = await request.json()
    payload = MobileMetricsPayload.model_validate(body)
    if payload.run_id != run_id:
        raise HTTPException(400, "run_id mismatch")

    path = tracker.save_mobile_metrics(payload.model_dump())
    now = datetime.now(timezone.utc).isoformat()
    with tracker.stage(
        "mobile_metrics_received",
        tool="viewer-web / iOS",
        inputs=[],
        outputs=[path],
        extra={"source": payload.extra.get("source", "client")},
    ):
        pass

    return JSONResponse({"ok": True, "path": str(path.relative_to(REPO_ROOT))})


# Static exports for manifest / scene.ply (viewer on phone loads from capture server)
_exports = DEFAULT_EXPORTS
_exports.mkdir(parents=True, exist_ok=True)
app.mount("/exports", StaticFiles(directory=str(_exports)), name="exports")

_runs = getattr(RunTracker, "RUNS_ROOT", REPO_ROOT / "runs")
_runs.mkdir(parents=True, exist_ok=True)
app.mount("/runs-files", StaticFiles(directory=str(_runs)), name="runs-files")


def main() -> None:
    uvicorn.run(app, host="0.0.0.0", port=8787)


if __name__ == "__main__":
    main()
