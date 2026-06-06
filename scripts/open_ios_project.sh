#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT/apps/capture-ios"
PROJECT="$IOS_DIR/SpatialCaptureRunner.xcodeproj"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

cd "$IOS_DIR"
xcodegen generate

if [[ "$(uname -s)" == "Darwin" ]]; then
  open "$PROJECT"
else
  echo "Generated $PROJECT"
  echo "Open it on a Mac with: open $PROJECT"
fi
