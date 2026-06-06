"""CLI smoke test: AR zip fixture → ingest → transforms (no ns-train)."""

from __future__ import annotations

import argparse
import shutil
import tempfile
import zipfile
from pathlib import Path

from spatial_asset_compiler.capture.unpack import unpack_ar_capture_zip
from spatial_asset_compiler.config import PROFILES, PipelinePaths, PipelineState
from spatial_asset_compiler.ingest.arkit import ingest_arkit
from spatial_asset_compiler.reconstruction.arkit_runner import run_arkit_reconstruction


def run_smoke(fixture: Path, scene_id: str = "arkit_smoke") -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        capture_dir = root / "captures" / scene_id
        output_dir = root / "exports" / scene_id
        unpack_ar_capture_zip(fixture, capture_dir)
        state = PipelineState(
            paths=PipelinePaths(
                scene_id=scene_id,
                capture_dir=capture_dir,
                output_dir=output_dir,
            ),
            profile=PROFILES["dev"],
        )
        ingest_arkit(state)
        run_arkit_reconstruction(state)
        transforms = output_dir / "reconstruction" / "ns_processed" / "transforms.json"
        debug = output_dir / "reconstruction" / "arkit_pose_debug.json"
        first = output_dir / "reconstruction" / "first_pose_debug.json"
        for p in (transforms, debug, first):
            if not p.exists():
                print(f"MISSING: {p}")
                return 1
        print(f"OK transforms={transforms}")
        print(f"OK debug={debug}")
        return 0


def main() -> None:
    ap = argparse.ArgumentParser(description="ARKit transforms smoke test")
    ap.add_argument(
        "--fixture",
        type=Path,
        default=Path("tests/fixtures/ar_capture_minimal.zip"),
    )
    ap.add_argument("--scene-id", default="arkit_smoke")
    args = ap.parse_args()
    raise SystemExit(run_smoke(args.fixture, args.scene_id))


if __name__ == "__main__":
    main()
