"""Minimal capture-upload server.

Accepts a captured video from the iOS app, stores it under
data/captures/<scene_id>/, and starts the Mobile-GS backend pipeline
(FFmpeg frames -> COLMAP dataset -> Mobile-GS train -> compress) as a
background task.

The server never renders or streams frames back to the client. The pipeline's
final artifact is a compressed Mobile-GS asset (comp.xz) that a native runtime
downloads and renders locally.

Run:
    pip install fastapi uvicorn python-multipart
    python server/capture-upload/app.py
"""

from __future__ import annotations

import json
import os
import subprocess
import threading
import time
from pathlib import Path

import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CAPTURES_DIR = REPO_ROOT / "data" / "captures"
OUTPUTS_DIR = REPO_ROOT / "training" / "mobile-gs" / "outputs"
LOGS_DIR = REPO_ROOT / "logs" / "capture-upload"
PIPELINE_SCRIPTS = [
    REPO_ROOT / "training" / "mobile-gs" / "prepare_frames.sh",
    REPO_ROOT / "training" / "mobile-gs" / "run_colmap.sh",
    REPO_ROOT / "training" / "mobile-gs" / "run_mobile_gs_train.sh",
    REPO_ROOT / "training" / "mobile-gs" / "run_mobile_gs_compress.sh",
]

app = FastAPI(title="capture-upload", version="1.0")
_lock = threading.Lock()


def _status_path(scene_id: str) -> Path:
    return CAPTURES_DIR / scene_id / "status.json"


def _write_status(scene_id: str, **fields) -> None:
    path = _status_path(scene_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"scene_id": scene_id, "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S")}
    payload.update(fields)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _read_status(scene_id: str) -> dict:
    path = _status_path(scene_id)
    if not path.exists():
        raise HTTPException(404, f"unknown scene_id: {scene_id}")
    return json.loads(path.read_text(encoding="utf-8"))


def _run_pipeline(scene_id: str) -> None:
    log_path = LOGS_DIR / f"{scene_id}.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["SCENE_ID"] = scene_id

    with open(log_path, "a", encoding="utf-8") as log:
        for script in PIPELINE_SCRIPTS:
            stage = script.stem
            _write_status(scene_id, status="running", stage=stage)
            log.write(f"\n=== {stage} ===\n")
            log.flush()
            proc = subprocess.run(
                ["bash", str(script), scene_id],
                cwd=str(REPO_ROOT),
                stdout=log,
                stderr=subprocess.STDOUT,
                env=env,
            )
            if proc.returncode != 0:
                _write_status(
                    scene_id,
                    status="failed",
                    stage=stage,
                    detail=f"{stage} exited {proc.returncode}; see {log_path}",
                )
                return

    artifact = OUTPUTS_DIR / scene_id / "comp.xz"
    if artifact.exists():
        _write_status(
            scene_id,
            status="completed",
            stage="done",
            artifact=str(artifact.relative_to(REPO_ROOT)),
        )
    else:
        _write_status(
            scene_id,
            status="failed",
            stage="done",
            detail=f"pipeline finished but {artifact} is missing",
        )


@app.post("/captures/{scene_id}")
async def upload_capture(
    scene_id: str,
    video: UploadFile = File(...),
    metadata: str = Form(default="{}"),
) -> dict:
    scene_dir = CAPTURES_DIR / scene_id
    scene_dir.mkdir(parents=True, exist_ok=True)

    suffix = Path(video.filename or "video.mov").suffix or ".mov"
    video_path = scene_dir / f"video{suffix}"
    data = await video.read()
    video_path.write_bytes(data)

    try:
        meta = json.loads(metadata)
    except json.JSONDecodeError:
        meta = {"raw": metadata}
    (scene_dir / "capture.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

    _write_status(scene_id, status="uploaded", stage="upload", bytes=len(data))
    with _lock:
        threading.Thread(target=_run_pipeline, args=(scene_id,), daemon=True).start()

    return {"scene_id": scene_id, "status": "started", "bytes": len(data)}


@app.get("/captures/{scene_id}/status")
def capture_status(scene_id: str) -> dict:
    return _read_status(scene_id)


@app.get("/captures/{scene_id}/asset")
def capture_asset(scene_id: str) -> FileResponse:
    artifact = OUTPUTS_DIR / scene_id / "comp.xz"
    if not artifact.exists():
        raise HTTPException(404, "compressed asset not ready")
    return FileResponse(artifact, filename="comp.xz")


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8787")))
