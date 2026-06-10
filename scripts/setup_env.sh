#!/usr/bin/env bash
# Prepare the backend environment for the Mobile-GS pipeline:
#   - FFmpeg + COLMAP (dataset preparation)
#   - conda env `mobile-gs` with CUDA PyTorch (Mobile-GS training/compression)
#   - Mobile-GS clone in third_party/
#   - optional: 3DGS.cpp clone for the native renderer (SETUP_RUNTIME=1)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY="$ROOT/third_party"
MOBILE_GS_DIR="$THIRD_PARTY/Mobile-GS"
RENDERER_DIR="$ROOT/runtime/vulkan-renderer/third_party/3DGS.cpp"
ENV_NAME="${MOBILE_GS_ENV:-mobile-gs}"

log() { echo "[setup_env] $*"; }

# --- system tools: ffmpeg + colmap ---------------------------------------
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v colmap >/dev/null 2>&1; then
  log "installing ffmpeg/colmap via apt (sudo required)"
  sudo apt-get update -qq
  sudo apt-get install -y ffmpeg colmap
else
  log "ffmpeg and colmap already installed"
fi

# --- Mobile-GS clone -------------------------------------------------------
mkdir -p "$THIRD_PARTY"
if [[ ! -d "$MOBILE_GS_DIR/.git" ]]; then
  log "cloning Mobile-GS"
  git clone --recursive https://github.com/xiaobiaodu/Mobile-GS "$MOBILE_GS_DIR"
else
  log "Mobile-GS already cloned"
fi

# --- conda env with CUDA PyTorch ------------------------------------------
if ! command -v conda >/dev/null 2>&1; then
  log "ERROR: conda not found — install Miniconda first" >&2
  exit 1
fi
source "$(conda info --base)/etc/profile.d/conda.sh"

if ! conda env list | grep -qE "^${ENV_NAME}[[:space:]]"; then
  log "creating conda env '$ENV_NAME' (python 3.11)"
  conda create -y -n "$ENV_NAME" python=3.11
fi
conda activate "$ENV_NAME"

log "installing PyTorch (cu118) + Mobile-GS requirements"
pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 \
  --index-url https://download.pytorch.org/whl/cu118
pip install -r "$MOBILE_GS_DIR/requirements.txt"

log "installing capture-upload server deps"
pip install fastapi uvicorn python-multipart

if ! command -v tmc3 >/dev/null 2>&1; then
  log "NOTE: tmc3 (MPEG GPCC) not on PATH — required by Mobile-GS compression."
  log "      Build from https://github.com/MPEGGroup/mpeg-pcc-tmc13 and add to PATH."
fi

# --- optional: native renderer base ----------------------------------------
if [[ "${SETUP_RUNTIME:-0}" == "1" ]]; then
  if [[ ! -d "$RENDERER_DIR/.git" ]]; then
    log "cloning 3DGS.cpp"
    git clone --recursive https://github.com/shg8/3DGS.cpp "$RENDERER_DIR"
  else
    log "3DGS.cpp already cloned"
  fi
else
  log "skipping 3DGS.cpp clone (set SETUP_RUNTIME=1 to enable)"
fi

log "done — run scripts/verify_deps.sh to check the environment"
