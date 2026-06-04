"""One-command spatial asset compiler pipeline."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

from spatial_asset_compiler.config import (
    DATA_CAPTURES,
    DEFAULT_EXPORTS,
    PROFILES,
    PipelinePaths,
    PipelineState,
    ProfileConfig,
)
from spatial_asset_compiler.pipeline import STAGES, execute_pipeline


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Spatial Asset Compiler")
    ap.add_argument("--scene-id", required=True)
    ap.add_argument("--output", type=Path, default=None)
    ap.add_argument(
        "--from-capture-dir",
        type=Path,
        default=None,
        help="Capture package dir (default: data/captures/{scene_id})",
    )
    ap.add_argument(
        "--profile",
        choices=list(PROFILES.keys()),
        default="dev",
    )
    ap.add_argument(
        "--stages",
        type=str,
        default=",".join(STAGES),
        help=f"Comma-separated stages. Default: all. Options: {','.join(STAGES)}",
    )
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    scene_id = args.scene_id
    capture_dir = args.from_capture_dir or (DATA_CAPTURES / scene_id)
    output_dir = args.output or (DEFAULT_EXPORTS / scene_id)
    profile: ProfileConfig = PROFILES[args.profile]
    stages = [s.strip() for s in args.stages.split(",") if s.strip()]

    paths = PipelinePaths(
        scene_id=scene_id,
        capture_dir=capture_dir.resolve(),
        output_dir=output_dir.resolve(),
    )
    paths.output_dir.mkdir(parents=True, exist_ok=True)
    paths.logs_dir.mkdir(parents=True, exist_ok=True)

    state = PipelineState(paths=paths, profile=profile)
    pipeline_log = Path("logs") / "pipeline" / f"{scene_id}.log"
    return execute_pipeline(state, stages, pipeline_log=pipeline_log)


if __name__ == "__main__":
    sys.exit(main())
