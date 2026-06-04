#!/usr/bin/env bash
# Run dependency diagnostics. Does not install or modify anything.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== Spatial Asset Compiler: doctor ==="
echo ""

echo "--- Default checks (main env) ---"
if bash "$ROOT/scripts/verify_deps.sh"; then
  DEFAULT_OK=1
else
  DEFAULT_OK=0
fi

echo ""
echo "--- Full checks (SAM2, heavy envs, viewer) ---"
if bash "$ROOT/scripts/verify_deps.sh" --full; then
  FULL_OK=1
else
  FULL_OK=0
fi

echo ""
echo "=== Summary ==="
if [[ "${DEFAULT_OK:-0}" -eq 1 ]]; then
  echo "Default: PASS"
else
  echo "Default: FAIL — fix main env first:"
  echo "  conda create -n spatial-asset-clean python=3.11 -y   # if missing"
  echo "  bash scripts/setup_third_party.sh --yes"
  echo "  bash scripts/setup_env.sh --yes"
fi

if [[ "${FULL_OK:-0}" -eq 1 ]]; then
  echo "Full:    PASS"
else
  echo "Full:    FAIL — additional manual steps:"
  echo "  bash scripts/download_sam2_checkpoints.sh"
  echo "  bash scripts/setup_heavy_envs.sh --yes"
  echo "  cd apps/viewer-web && npm install"
fi

if [[ "${DEFAULT_OK:-0}" -eq 1 && "${FULL_OK:-0}" -eq 1 ]]; then
  exit 0
fi
exit 1
