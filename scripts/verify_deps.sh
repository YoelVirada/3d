#!/usr/bin/env bash
# Verify the Mobile-GS pipeline environment. Checks:
#   - Xcode/XcodeGen (iOS capture; macOS only)
#   - FFmpeg
#   - COLMAP
#   - CUDA / PyTorch in the mobile-gs env
#   - Mobile-GS repository
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_NAME="${MOBILE_GS_ENV:-mobile-gs}"
FAIL=0

ok()   { echo "  OK   $*"; }
warn() { echo "  WARN $*"; }
bad()  { echo "  FAIL $*"; FAIL=1; }

echo "== iOS capture (Xcode/XcodeGen) =="
if [[ "$(uname -s)" == "Darwin" ]]; then
  command -v xcodebuild >/dev/null && ok "xcodebuild $(xcodebuild -version | head -1)" || bad "xcodebuild missing (install Xcode)"
  command -v xcodegen >/dev/null && ok "xcodegen $(xcodegen --version)" || bad "xcodegen missing (brew install xcodegen)"
else
  warn "not macOS — iOS app must be generated/built on a Mac (scripts/open_ios_project.sh)"
fi
[[ -f "$ROOT/apps/ios-capture/project.yml" ]] && ok "apps/ios-capture/project.yml present" || bad "apps/ios-capture/project.yml missing"

echo "== FFmpeg =="
if command -v ffmpeg >/dev/null; then
  ok "$(ffmpeg -version 2>/dev/null | head -1)"
else
  bad "ffmpeg missing (scripts/setup_env.sh)"
fi

echo "== COLMAP =="
if command -v colmap >/dev/null; then
  ok "colmap $(colmap help 2>&1 | grep -m1 -oP 'COLMAP \K[0-9.]+' || echo '(version unknown)')"
else
  bad "colmap missing (scripts/setup_env.sh)"
fi

echo "== CUDA / PyTorch (env: $ENV_NAME) =="
if command -v conda >/dev/null; then
  source "$(conda info --base)/etc/profile.d/conda.sh"
  if conda env list | grep -qE "^${ENV_NAME}[[:space:]]"; then
    conda activate "$ENV_NAME"
    TORCH_INFO="$(python - <<'PY' 2>/dev/null
import torch
print(f"torch {torch.__version__} cuda_available={torch.cuda.is_available()} cuda={torch.version.cuda}")
PY
)" || TORCH_INFO=""
    if [[ -n "$TORCH_INFO" ]]; then
      if [[ "$TORCH_INFO" == *"cuda_available=True"* ]]; then
        ok "$TORCH_INFO"
      else
        bad "$TORCH_INFO — CUDA GPU not visible to PyTorch"
      fi
    else
      bad "torch not importable in env '$ENV_NAME'"
    fi
  else
    bad "conda env '$ENV_NAME' missing (scripts/setup_env.sh)"
  fi
else
  bad "conda missing"
fi

echo "== Mobile-GS repository =="
MOBILE_GS_DIR="${MOBILE_GS_DIR:-$ROOT/third_party/Mobile-GS}"
if [[ -d "$MOBILE_GS_DIR/.git" ]]; then
  ok "Mobile-GS at $MOBILE_GS_DIR"
  [[ -f "$MOBILE_GS_DIR/train.py" && -f "$MOBILE_GS_DIR/render.py" ]] \
    && ok "train.py / render.py present" \
    || warn "expected train.py/render.py not found — check Mobile-GS checkout"
else
  bad "Mobile-GS missing at $MOBILE_GS_DIR (scripts/setup_env.sh)"
fi
command -v tmc3 >/dev/null && ok "tmc3 (GPCC) on PATH" || warn "tmc3 not on PATH — required by Mobile-GS compression"

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "All required dependencies verified."
else
  echo "Some dependencies are missing — see FAIL lines above."
fi
exit "$FAIL"
