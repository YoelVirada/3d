#!/usr/bin/env bash
# Mobile-GS training. Mobile-GS is treated as a black-box tool; this wrapper
# only sets paths. Internals live in third_party/Mobile-GS (do not modify).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCENE="${1:-${SCENE_ID:?usage: run_mobile_gs_train.sh <scene_id>}}"

MOBILE_GS="${MOBILE_GS_DIR:-$ROOT/third_party/Mobile-GS}"
DATASET="$ROOT/training/mobile-gs/outputs/$SCENE/dataset"
MODEL="$ROOT/training/mobile-gs/outputs/$SCENE/model"
CONDA_ENV="${MOBILE_GS_ENV:-mobile-gs}"

[[ -d "$MOBILE_GS" ]] || { echo "ERROR: Mobile-GS repo missing at $MOBILE_GS — run scripts/setup_env.sh" >&2; exit 1; }
[[ -d "$DATASET/sparse/0" ]] || { echo "ERROR: COLMAP dataset missing — run run_colmap.sh first" >&2; exit 1; }

mkdir -p "$MODEL"

echo "[mobile_gs_train] dataset=$DATASET model=$MODEL env=$CONDA_ENV"
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$CONDA_ENV"

cd "$MOBILE_GS"
python train.py \
  -s "$DATASET" \
  -m "$MODEL" \
  ${MOBILE_GS_TRAIN_ARGS:-}

echo "[mobile_gs_train] done — model at $MODEL"
