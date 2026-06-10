#!/usr/bin/env bash
# Mobile-GS compression. Produces the exact compressed artifact Mobile-GS
# generates (comp.xz) and copies it to outputs/<scene>/comp.xz.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCENE="${1:-${SCENE_ID:?usage: run_mobile_gs_compress.sh <scene_id>}}"

MOBILE_GS="${MOBILE_GS_DIR:-$ROOT/third_party/Mobile-GS}"
DATASET="$ROOT/training/mobile-gs/outputs/$SCENE/dataset"
MODEL="$ROOT/training/mobile-gs/outputs/$SCENE/model"
FINAL="$ROOT/training/mobile-gs/outputs/$SCENE/comp.xz"
CONDA_ENV="${MOBILE_GS_ENV:-mobile-gs}"

[[ -d "$MOBILE_GS" ]] || { echo "ERROR: Mobile-GS repo missing at $MOBILE_GS — run scripts/setup_env.sh" >&2; exit 1; }
[[ -d "$MODEL" ]] || { echo "ERROR: model missing — run run_mobile_gs_train.sh first" >&2; exit 1; }

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$CONDA_ENV"

cd "$MOBILE_GS"
# Mobile-GS emits the compressed asset alongside the model during/after
# training; render.py --decode validates that decoding the compressed file
# reproduces the PLY-path results (CUDA reference decoder).
python render.py -s "$DATASET" -m "$MODEL" --decode ${MOBILE_GS_COMPRESS_ARGS:-}

COMP="$(find "$MODEL" -name 'comp.xz' | head -1 || true)"
if [[ -z "$COMP" ]]; then
  echo "ERROR: comp.xz not found under $MODEL — check Mobile-GS output layout" >&2
  exit 1
fi

cp -f "$COMP" "$FINAL"
echo "[mobile_gs_compress] artifact: $FINAL ($(stat -c%s "$FINAL") bytes)"
