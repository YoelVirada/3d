from spatial_asset_compiler.capture.mode import detect_capture_mode
from spatial_asset_compiler.ingest.arkit import ingest_arkit
from spatial_asset_compiler.ingest.video import extract_frames, load_capture_package


def run_ingest(state):
    from spatial_asset_compiler.config import PipelineState

    assert isinstance(state, PipelineState)
    mode = detect_capture_mode(state.paths.capture_dir)
    state.benchmarks["capture_mode"] = mode
    if mode == "arkit":
        return ingest_arkit(state)
    return extract_frames(state)


__all__ = ["run_ingest", "extract_frames", "load_capture_package", "ingest_arkit"]
