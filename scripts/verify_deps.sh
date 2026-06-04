#!/usr/bin/env bash
# Verify setup. Default: main env (spatial-asset-clean). --full: SAM2 ckpts, heavy envs, viewer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/third_party/versions.lock.json"
ENV_NAME="spatial-asset-clean"
FULL=0
FAIL=0

if [[ "${1:-}" == "--full" ]]; then
  FULL=1
fi

ok() { echo "OK  $*"; }
fail() { echo "FAIL $*"; FAIL=1; }
warn() { echo "WARN $*"; }

check_cmd() {
  if command -v "$1" &>/dev/null; then
    ok "$1: $(command -v "$1")"
  else
    fail "$1 missing — $2"
  fi
}

check_path_banned() {
  if echo "$PATH" | tr ':' '\n' | grep -qE "$1"; then
    fail "PATH contains banned segment: $1"
  else
    ok "PATH clean of $1"
  fi
}

conda_py() {
  conda run -n "$ENV_NAME" python "$@"
}

echo "=== verify_deps.sh mode=$([[ $FULL -eq 1 ]] && echo full || echo default) ==="

echo ""
echo "=== System tools ==="
check_cmd ffmpeg "sudo apt install ffmpeg"
check_cmd ffprobe "sudo apt install ffmpeg"
check_cmd colmap "sudo apt install colmap"
check_cmd nvidia-smi "NVIDIA driver required"
check_cmd node "Install Node 20+ for viewer-web"

echo ""
echo "=== Banned legacy paths (must not be on PATH) ==="
check_path_banned "stable-3d"
check_path_banned "colmap-cuda"
check_path_banned "/3dgs"
check_path_banned "maskgen"

echo ""
echo "=== Conda env: $ENV_NAME ==="
if ! conda env list | grep -qE "^${ENV_NAME}[[:space:]]"; then
  fail "conda env $ENV_NAME missing — conda create -n $ENV_NAME python=3.11 -y"
else
  ok "conda env $ENV_NAME exists"
fi

echo ""
echo "=== Python / torch / CUDA (main env) ==="
if ! conda_py -c "import torch; print(torch.__version__)" 2>/dev/null; then
  fail "torch import — run scripts/setup_env.sh --yes"
else
  TV="$(conda_py -c "import torch; print(torch.__version__)")"
  if [[ "$TV" == *"2.6.0+cu124"* ]]; then
    ok "torch $TV"
  else
    fail "torch version '$TV' (expected 2.6.0+cu124)"
  fi
  if conda_py -c "import torch; assert torch.cuda.is_available()"; then
    ok "torch.cuda.is_available()"
  else
    fail "CUDA not available in torch"
  fi
fi

if ! conda_py -c "import torchvision; print(torchvision.__version__)" 2>/dev/null; then
  fail "torchvision import"
else
  TVV="$(conda_py -c "import torchvision; print(torchvision.__version__)")"
  if [[ "$TVV" == *"0.21.0+cu124"* ]]; then
    ok "torchvision $TVV"
  else
    fail "torchvision '$TVV' (expected 0.21.0+cu124)"
  fi
fi

echo ""
echo "=== numpy / opencv ==="
if conda_py -c "import numpy as np; assert np.__version__.startswith('1.'); print(np.__version__)" 2>/dev/null; then
  ok "numpy $(conda_py -c 'import numpy; print(numpy.__version__)')"
else
  fail "numpy must be 1.x (not 2.x)"
fi

if conda_py -c "import cv2; print(cv2.__version__)" 2>/dev/null; then
  CV="$(conda_py -c "import cv2; print(cv2.__version__)")"
  if [[ "$CV" == 4.10.0* ]]; then
    ok "cv2 $CV"
  else
    fail "cv2 version '$CV' (expected 4.10.0.x)"
  fi
else
  fail "cv2 import — pip install opencv-python-headless==4.10.0.84"
fi

echo ""
echo "=== nerfstudio CLI ==="
for cmd in ns-process-data ns-train ns-export; do
  if conda run -n "$ENV_NAME" bash -c "command -v $cmd" &>/dev/null; then
    ok "$cmd"
  else
    fail "$cmd — pip install -e third_party/nerfstudio"
  fi
done

if conda_py -c "import nerfstudio" 2>/dev/null; then
  ok "import nerfstudio"
else
  fail "import nerfstudio"
fi

echo ""
echo "=== gsplat (editable v1.4.0 from third_party) ==="
if [[ ! -d "$ROOT/third_party/gsplat/.git" ]]; then
  fail "third_party/gsplat missing"
else
  GS_HEAD="$(git -C "$ROOT/third_party/gsplat" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  GS_TAG="$(git -C "$ROOT/third_party/gsplat" describe --tags --exact-match 2>/dev/null || echo none)"
  if git -C "$ROOT/third_party/gsplat" rev-parse v1.4.0 &>/dev/null; then
    CURRENT="$(git -C "$ROOT/third_party/gsplat" rev-parse HEAD)"
    TAG_COMMIT="$(git -C "$ROOT/third_party/gsplat" rev-parse v1.4.0^{commit})"
    if [[ "$CURRENT" == "$TAG_COMMIT" ]] || [[ "$GS_TAG" == "v1.4.0" ]]; then
      ok "third_party/gsplat at v1.4.0 ($GS_HEAD)"
    else
      fail "third_party/gsplat not at v1.4.0 (HEAD=$GS_HEAD tag=$GS_TAG)"
    fi
  else
    fail "third_party/gsplat: tag v1.4.0 not found — run scripts/setup_third_party.sh --yes"
  fi
fi

if conda_py -c "
import gsplat
from gsplat.rendering import rasterization
import os
v = getattr(gsplat, '__version__', 'unknown')
assert v == '1.4.0', v
f = gsplat.__file__
assert 'third_party/gsplat' in f.replace(chr(92), '/'), f
print(v, f)
" 2>/dev/null; then
  ok "gsplat import + rasterization + version 1.4.0 + third_party path"
else
  fail "gsplat — reinstall with scripts/setup_env.sh --yes"
fi

echo ""
echo "=== pip check (main env) ==="
if conda run -n "$ENV_NAME" python -m pip check 2>/dev/null; then
  ok "pip check"
else
  fail "pip check — dependency conflicts present"
fi

echo ""
echo "=== third_party clones ==="
for d in nerfstudio gsplat sam2 SegAnyGAussians gaussian-grouping; do
  if [[ -d "$ROOT/third_party/$d/.git" ]]; then
    ok "third_party/$d"
  else
    fail "third_party/$d — bash scripts/setup_third_party.sh --yes"
  fi
done

if [[ $FULL -eq 0 ]]; then
  echo ""
  echo "=== Heavy-stage envs (not required in default mode) ==="
  for e in saga-lift gaussian-grouping sugar-mesh; do
    if conda env list | grep -qE "^${e}[[:space:]]"; then
      ok "$e exists"
    else
      warn "$e not installed — run scripts/setup_heavy_envs.sh --yes for full pipeline"
    fi
  done
  echo ""
  if [[ $FAIL -eq 0 ]]; then
    echo "Default verification passed."
    echo "For full checks: bash scripts/verify_deps.sh --full"
    exit 0
  else
    echo "Default verification failed."
    exit 1
  fi
fi

echo ""
echo "=== FULL: SAM2 ==="
if conda_py -c "import sam2" 2>/dev/null; then
  ok "import sam2"
else
  fail "import sam2"
fi
for ck in sam2.1_hiera_small.pt sam2.1_hiera_base_plus.pt; do
  p="$ROOT/third_party/checkpoints/sam2/$ck"
  if [[ -f "$p" ]] && [[ -s "$p" ]]; then
    ok "checkpoint $ck ($(stat -c%s "$p" 2>/dev/null || stat -f%z "$p") bytes)"
  else
    fail "checkpoint missing/empty: $p — bash scripts/download_sam2_checkpoints.sh"
  fi
done

echo ""
echo "=== FULL: isolated heavy-stage envs ==="
STATUS_FILE="$ROOT/logs/setup/heavy_envs_status.json"
if [[ -f "$STATUS_FILE" ]]; then
  ok "heavy_envs_status.json present"
  python3 -c "
import json, sys
d=json.load(open(sys.argv[1]))
for env, info in d.get('environments', {}).items():
    st=info.get('status','unknown')
    print(f'  {env}: {st}')
    if st not in ('ready',):
        sys.exit(1)
" "$STATUS_FILE" && ok "all heavy envs status=ready" || fail "heavy envs incomplete — bash scripts/setup_heavy_envs.sh --yes"
else
  fail "missing $STATUS_FILE — run scripts/setup_heavy_envs.sh --yes"
fi

for e in saga-lift sugar-mesh; do
  if ! conda env list | grep -qE "^${e}[[:space:]]"; then
    fail "conda env $e missing"
  else
    if conda run -n "$e" python -c "import torch" 2>/dev/null; then
      ok "$e: torch import"
    else
      fail "$e: torch import failed"
    fi
  fi
done

echo ""
echo "=== FULL: gaussian-grouping runtime (torch + CUDA extensions) ==="
if ! conda env list | grep -qE "^gaussian-grouping[[:space:]]"; then
  fail "conda env gaussian-grouping missing"
elif conda run -n gaussian-grouping --no-capture-output bash -lc '
TORCH_LIB=$(python -c "import torch, pathlib; print(pathlib.Path(torch.__file__).parent / \"lib\")")
export LD_LIBRARY_PATH="$TORCH_LIB:$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}"
python -c "
import torch
from diff_gaussian_rasterization import GaussianRasterizationSettings, GaussianRasterizer
from simple_knn._C import distCUDA2
print(torch.__version__, torch.version.cuda)
"
' 2>/dev/null; then
  ok "gaussian-grouping: torch + diff_gaussian_rasterization + simple_knn._C runtime import"
else
  fail "gaussian-grouping: runtime import failed — run scripts/setup_heavy_envs.sh --yes (needs simple_knn/ package dir + torch lib on LD_LIBRARY_PATH)"
fi

echo ""
echo "=== FULL: viewer-web ==="
VW="$ROOT/apps/viewer-web"
if [[ -f "$VW/package.json" && -f "$VW/src/asset/SpatialAssetLoader.ts" && -f "$VW/src/main.ts" ]]; then
  ok "viewer-web package files"
else
  fail "viewer-web skeleton incomplete"
fi
if [[ -f "$VW/package.json" ]] && grep -q '"dev"' "$VW/package.json"; then
  ok "viewer-web npm run dev defined"
else
  fail "viewer-web missing dev script"
fi

echo ""
echo "=== FULL: mobile benchmark templates ==="
if [[ -f "$ROOT/spatial_asset_compiler/asset/package.py" ]]; then
  ok "package finalizer (writes mobile_benchmarks templates)"
else
  warn "asset package module not found"
fi

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "Full verification passed."
  exit 0
else
  echo "Full verification failed."
  exit 1
fi
