#!/usr/bin/env bash
# Install main conda env (spatial-asset-clean) with pinned CUDA stack.
# Prerequisite: bash scripts/setup_third_party.sh --yes
# Does NOT download SAM2 checkpoints — run download_sam2_checkpoints.sh separately.
# Requires: --yes  or  SAC_ALLOW_MAIN_ENV_SETUP=1
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

_sac_approved=0
for _arg in "$@"; do
  [[ "$_arg" == "--yes" ]] && _sac_approved=1
done
if [[ "$_sac_approved" != 1 && -z "${SAC_ALLOW_MAIN_ENV_SETUP:-}" ]]; then
  cat <<'EOF'
Refusing to modify spatial-asset-clean (reinstalls torch, gsplat, nerfstudio, sam2, etc.).

Approve explicitly:
  bash scripts/setup_env.sh --yes
  SAC_ALLOW_MAIN_ENV_SETUP=1 bash scripts/setup_env.sh
EOF
  exit 1
fi

ENV_NAME="${CONDA_ENV:-spatial-asset-clean}"
CONSTRAINTS="$ROOT/constraints/main-cu124.txt"
GSPLAT_DIR="$ROOT/third_party/gsplat"
GSPLAT_TAG="v1.4.0"
SAM2_DIR="$ROOT/third_party/sam2"
NERFSTUDIO_DIR="$ROOT/third_party/nerfstudio"

echo "=== Spatial Asset Compiler: setup_env ==="
echo "Target conda env: $ENV_NAME"

if ! command -v conda &>/dev/null; then
  echo "ERROR: conda not found"
  exit 1
fi

source "$(conda info --base)/etc/profile.d/conda.sh"

if ! conda env list | grep -qE "^${ENV_NAME}[[:space:]]"; then
  echo "ERROR: conda env '$ENV_NAME' does not exist."
  echo "Create it manually: conda create -n $ENV_NAME python=3.11 -y"
  exit 1
fi

conda activate "$ENV_NAME"

if [[ "$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')" != "3.11" ]]; then
  echo "ERROR: $ENV_NAME must use Python 3.11"
  exit 1
fi

python -m pip install --upgrade pip wheel setuptools

echo "=== Installing pinned torch stack (cu124) ==="
python -m pip install \
  torch==2.6.0+cu124 \
  torchvision==0.21.0+cu124 \
  --index-url https://download.pytorch.org/whl/cu124

python -c "import torch; assert torch.cuda.is_available(), 'CUDA not available'"

echo "=== OpenCV headless (no GUI wheel) ==="
python -m pip uninstall -y opencv-python 2>/dev/null || true
python -m pip install --force-reinstall --no-deps opencv-python-headless==4.10.0.84

echo "=== Main package (editable) ==="
python -m pip install -e "$ROOT"

if [[ ! -d "$NERFSTUDIO_DIR/.git" ]]; then
  echo "ERROR: $NERFSTUDIO_DIR missing. Run: bash scripts/setup_third_party.sh --yes"
  exit 1
fi
echo "=== Nerfstudio (editable) ==="
python -m pip install -e "$NERFSTUDIO_DIR"

if [[ ! -d "$GSPLAT_DIR/.git" ]]; then
  echo "ERROR: third_party/gsplat missing. Run: bash scripts/setup_third_party.sh --yes"
  exit 1
fi

echo "=== gsplat: enforce $GSPLAT_TAG + submodules ==="
git -C "$GSPLAT_DIR" fetch --tags --force
git -C "$GSPLAT_DIR" checkout "$GSPLAT_TAG"
git -C "$GSPLAT_DIR" submodule update --init --recursive

export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-7.5}"
export MAX_JOBS="${MAX_JOBS:-4}"
echo "TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST MAX_JOBS=$MAX_JOBS"

echo "=== gsplat (editable, --no-build-isolation) ==="
python -m pip install --no-build-isolation -e "$GSPLAT_DIR"

if [[ ! -d "$SAM2_DIR/.git" ]]; then
  echo "ERROR: $SAM2_DIR missing. Run: bash scripts/setup_third_party.sh --yes"
  exit 1
fi
echo "=== SAM2 (editable, required — after torch) ==="
python -m pip install -e "$SAM2_DIR"

echo "=== pip check ==="
python -m pip check

echo "=== setup_env complete ==="
echo "Next (manual):"
echo "  bash scripts/download_sam2_checkpoints.sh"
echo "  bash scripts/setup_heavy_envs.sh --yes"
echo "  bash scripts/verify_deps.sh"
echo "  bash scripts/verify_deps.sh --full"
