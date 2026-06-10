#!/usr/bin/env bash
# COLMAP dataset preparation in the layout Mobile-GS expects
# (images/ + sparse/0/ — standard 3DGS-style COLMAP dataset).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCENE="${1:-${SCENE_ID:?usage: run_colmap.sh <scene_id>}}"

DATASET="$ROOT/training/mobile-gs/outputs/$SCENE/dataset"
IMAGES="$DATASET/images"
DB="$DATASET/database.db"
SPARSE="$DATASET/sparse"

command -v colmap >/dev/null || { echo "ERROR: colmap not installed" >&2; exit 1; }
[[ -d "$IMAGES" ]] || { echo "ERROR: $IMAGES missing — run prepare_frames.sh first" >&2; exit 1; }

rm -f "$DB"
rm -rf "$SPARSE"
mkdir -p "$SPARSE"

echo "[run_colmap] feature extraction"
colmap feature_extractor \
  --database_path "$DB" \
  --image_path "$IMAGES" \
  --ImageReader.single_camera 1 \
  --ImageReader.camera_model OPENCV \
  --SiftExtraction.use_gpu "${COLMAP_USE_GPU:-1}"

echo "[run_colmap] matching"
colmap exhaustive_matcher \
  --database_path "$DB" \
  --SiftMatching.use_gpu "${COLMAP_USE_GPU:-1}"

echo "[run_colmap] sparse mapping"
colmap mapper \
  --database_path "$DB" \
  --image_path "$IMAGES" \
  --output_path "$SPARSE"

[[ -d "$SPARSE/0" ]] || { echo "ERROR: COLMAP mapper produced no model" >&2; exit 1; }

N_IMAGES="$(ls "$IMAGES" | wc -l)"
N_REG="$(colmap model_analyzer --path "$SPARSE/0" 2>&1 | grep -oP 'Registered images:\s*\K\d+' || echo '?')"
echo "[run_colmap] done — registered $N_REG / $N_IMAGES images, model at $SPARSE/0"
