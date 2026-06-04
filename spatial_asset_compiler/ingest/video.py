"""Video ingest from iPhone capture package via FFmpeg."""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

from spatial_asset_compiler.config import PipelineState
from spatial_asset_compiler.utils.subprocess_runner import run_command


def load_capture_package(capture_dir: Path) -> tuple[Path, dict]:
    if not capture_dir.is_dir():
        raise FileNotFoundError(
            f"Capture package not found: {capture_dir}\n"
            "Upload from iPhone via capture server: POST /captures/{scene_id}"
        )
    videos = sorted(capture_dir.glob("video.*"))
    if not videos:
        raise FileNotFoundError(
            f"No video.* in {capture_dir}. Use apps/capture-ios or curl upload."
        )
    meta: dict = {}
    cap_json = capture_dir / "capture.json"
    if cap_json.exists():
        meta = json.loads(cap_json.read_text(encoding="utf-8"))
    return videos[0], meta


def _probe_video(video_path: Path) -> dict:
    cmd = [
        "ffprobe",
        "-v",
        "quiet",
        "-print_format",
        "json",
        "-show_format",
        "-show_streams",
        str(video_path),
    ]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(out.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return {}


def extract_frames(state: PipelineState) -> dict:
    p = state.paths
    video_path, capture_meta = load_capture_package(p.capture_dir)
    frames_dir = p.frames_dir
    frames_dir.mkdir(parents=True, exist_ok=True)

    stride = state.profile.frame_stride
    # fps filter: select every Nth frame
    pattern = str(frames_dir / "frame_%05d.jpg")
    cmd = [
        "ffmpeg",
        "-y",
        "-i",
        str(video_path),
        "-vf",
        f"select=not(mod(n\\,{stride}))",
        "-vsync",
        "vfr",
        "-qscale:v",
        "2",
        pattern,
    ]
    log = p.logs_dir / "ingest_ffmpeg.log"
    run_command(
        cmd,
        log_path=log,
        hint="Install FFmpeg: sudo apt install ffmpeg",
    )

    frames = sorted(frames_dir.glob("frame_*.jpg"))
    probe = _probe_video(video_path)
    duration_s = None
    fps = None
    width = height = None
    if probe.get("format", {}).get("duration"):
        duration_s = float(probe["format"]["duration"])
    for stream in probe.get("streams", []):
        if stream.get("codec_type") == "video":
            fps_s = stream.get("avg_frame_rate", "0/1")
            if "/" in str(fps_s):
                num, den = fps_s.split("/")
                if float(den) != 0:
                    fps = float(num) / float(den)
            width = stream.get("width")
            height = stream.get("height")
            break

    meta = {
        "frame_count": len(frames),
        "frame_stride": stride,
        "resolution": f"{width}x{height}" if width and height else capture_meta.get("resolution"),
        "fps": fps or capture_meta.get("fps"),
        "duration_s": duration_s or capture_meta.get("duration_s"),
        "source_video": str(video_path.name),
        "capture": capture_meta,
    }
    (p.output_dir / "frames_metadata.json").write_text(
        json.dumps(meta, indent=2), encoding="utf-8"
    )
    state.benchmarks.setdefault("ingest", {})
    state.benchmarks["ingest"].update(
        {
            "frame_count": len(frames),
            "extraction_time_s": state.benchmarks.get("_ingest_time_s"),
            "resolution": meta["resolution"],
            "fps": meta.get("fps"),
            "duration_s": meta.get("duration_s"),
        }
    )
    return meta
