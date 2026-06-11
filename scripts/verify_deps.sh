#!/usr/bin/env bash
# Verify iOS capture toolchain (XcodeGen + Xcode on macOS).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

ok()   { echo "  OK   $*"; }
warn() { echo "  WARN $*"; }
bad()  { echo "  FAIL $*"; FAIL=1; }

echo "== iOS capture (Xcode / XcodeGen) =="
if [[ "$(uname -s)" == "Darwin" ]]; then
  command -v xcodebuild >/dev/null && ok "xcodebuild $(xcodebuild -version | head -1)" || bad "xcodebuild missing (install Xcode)"
  command -v xcodegen >/dev/null && ok "xcodegen $(xcodegen --version)" || bad "xcodegen missing (brew install xcodegen)"
else
  warn "not macOS — generate/build the iOS app on a Mac (scripts/open_ios_project.sh)"
fi

[[ -f "$ROOT/apps/ios-capture/project.yml" ]] && ok "apps/ios-capture/project.yml present" || bad "project.yml missing"

echo "== Swift module layout =="
for dir in App Capture Dataset MsplatBridge Training Rendering Diagnostics; do
  [[ -d "$ROOT/apps/ios-capture/SpatialCapture/$dir" ]] \
    && ok "SpatialCapture/$dir/" \
    || bad "SpatialCapture/$dir/ missing"
done

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "iOS capture toolchain verified."
else
  echo "Some checks failed — see FAIL lines above."
fi
exit "$FAIL"
