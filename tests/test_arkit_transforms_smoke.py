import json
from pathlib import Path

from spatial_asset_compiler.reconstruction.arkit_smoke import run_smoke

FIXTURE = Path(__file__).parent / "fixtures" / "ar_capture_minimal.zip"


def test_transforms_smoke():
    assert FIXTURE.exists()
    assert run_smoke(FIXTURE) == 0


def test_debug_json_fields():
    import tempfile

    from spatial_asset_compiler.capture.unpack import unpack_ar_capture_zip
    from spatial_asset_compiler.config import PROFILES, PipelinePaths, PipelineState
    from spatial_asset_compiler.ingest.arkit import ingest_arkit
    from spatial_asset_compiler.reconstruction.arkit_runner import run_arkit_reconstruction

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        capture_dir = root / "captures" / "t"
        output_dir = root / "exports" / "t"
        unpack_ar_capture_zip(FIXTURE, capture_dir)
        state = PipelineState(
            paths=PipelinePaths(scene_id="t", capture_dir=capture_dir, output_dir=output_dir),
            profile=PROFILES["dev"],
        )
        ingest_arkit(state)
        run_arkit_reconstruction(state)
        debug = json.loads(
            (output_dir / "reconstruction" / "arkit_pose_debug.json").read_text()
        )
        assert debug["colmap_skipped"] is True
        assert debug["accepted_count"] > 0
        assert "first_pose" in debug
        assert "pose_bounds" in debug
