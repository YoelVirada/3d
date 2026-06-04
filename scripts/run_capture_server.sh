#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate spatial-asset-clean
cd "$ROOT"
echo "Capture server on http://0.0.0.0:8787"
echo "POST /captures/{scene_id} — upload + start pipeline (returns run_id)"
echo "GET  /runs/{run_id}/status | /result | /report"
echo "POST /runs/{run_id}/mobile-metrics"
echo "Static exports: http://<host>:8787/exports/<scene_id>/manifest.json"
echo "Set SAC_PUBLIC_BASE_URL and SAC_VIEWER_BASE_URL for iPhone LAN URLs"
python -m spatial_asset_compiler.capture_server
