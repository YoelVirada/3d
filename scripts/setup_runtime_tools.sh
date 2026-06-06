#!/usr/bin/env bash
# Install optional runtime asset CLI tools (@playcanvas/splat-transform).
# Does not modify Nerfstudio, gsplat, or third_party Python packages.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools/runtime"

if ! command -v node &>/dev/null; then
  echo "ERROR: node is required. Install Node.js 20+." >&2
  exit 1
fi
if ! command -v npm &>/dev/null; then
  echo "ERROR: npm is required." >&2
  exit 1
fi

echo "=== Spatial Asset Compiler: setup_runtime_tools ==="
cd "$TOOLS"
npm install

if [[ -x "$TOOLS/node_modules/.bin/splat-transform" ]]; then
  "$TOOLS/node_modules/.bin/splat-transform" --version
  echo "OK  splat-transform installed at tools/runtime/node_modules/.bin/splat-transform"
else
  echo "ERROR: splat-transform binary missing after npm install" >&2
  exit 1
fi

echo "Optional runtime conversion ready. Pipeline stage: runtime_asset"
