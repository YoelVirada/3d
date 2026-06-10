#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT/apps/ios-capture"
PROJECT="$IOS_DIR/SpatialCaptureRunner.xcodeproj"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

export IOS_BUNDLE_ID="${IOS_BUNDLE_ID:-com.yoel.spatialcapture}"
export IOS_DEVELOPMENT_TEAM="${IOS_DEVELOPMENT_TEAM:-}"

if [[ -z "$IOS_DEVELOPMENT_TEAM" ]]; then
  echo "IOS_DEVELOPMENT_TEAM is not set. Xcode signing will require manual team selection." >&2
  echo "Set your Apple Developer Team ID before generating:" >&2
  echo "  export IOS_DEVELOPMENT_TEAM=YOUR_TEAM_ID" >&2
  echo "  export IOS_BUNDLE_ID=com.yourname.spatialcapture  # optional, default: com.yoel.spatialcapture" >&2
  echo >&2
fi

cd "$IOS_DIR"
xcodegen generate

if [[ "$(uname -s)" == "Darwin" ]]; then
  open "$PROJECT"
else
  echo "Generated $PROJECT"
  echo "Open it on a Mac with: open $PROJECT"
fi
