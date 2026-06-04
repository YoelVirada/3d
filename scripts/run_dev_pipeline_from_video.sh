#!/usr/bin/env bash
# DEBUG ONLY: local video upload + CLI pipeline (no iPhone render metrics / runs/ report).
# Official proof: iPhone app → capture server background pipeline → viewer URL → mobile-metrics.
# Long-running GPU work (ingest → reconstruction → splats → segment → lift → mesh → package).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENE_ID="${1:-}"
VIDEO="${2:-}"

if [[ "${SAC_RUN_FULL_PIPELINE:-}" != "1" ]]; then
  cat <<'EOF'
Refusing to run the full dev pipeline (upload + all GPU stages).

Approve explicitly:
  SAC_RUN_FULL_PIPELINE=1 bash scripts/run_dev_pipeline_from_video.sh <scene_id> <path/to/video.mov>

Requires capture server in another terminal:
  bash scripts/run_capture_server.sh
EOF
  exit 1
fi

if [[ -z "$SCENE_ID" || -z "$VIDEO" ]]; then
  echo "Usage: SAC_RUN_FULL_PIPELINE=1 bash scripts/run_dev_pipeline_from_video.sh <scene_id> <path/to/video.mov>"
  exit 1
fi

if [[ ! -f "$VIDEO" ]]; then
  echo "ERROR: video file not found: $VIDEO"
  exit 1
fi

curl -sf -X POST "http://127.0.0.1:8787/captures/${SCENE_ID}" \
  -F "video=@${VIDEO}" \
  -F 'metadata={"device_model":"dev-sim","timestamp":"2026-06-03"}' \
  || {
    echo "ERROR: upload failed. Is capture server running? bash scripts/run_capture_server.sh"
    exit 1
  }

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate spatial-asset-clean
cd "$ROOT"
python -m spatial_asset_compiler.run --scene-id "$SCENE_ID" --profile dev
