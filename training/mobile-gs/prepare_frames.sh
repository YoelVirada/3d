#!/usr/bin/env bash
# FFmpeg frame extraction: data/captures/<scene>/video.* -> dataset/images/
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCENE="${1:-${SCENE_ID:?usage: prepare_frames.sh <scene_id>}}"

CAPTURE_DIR="$ROOT/data/captures/$SCENE"
OUT="$ROOT/training/mobile-gs/outputs/$SCENE/dataset/images"
FPS="${FRAME_FPS:-2}"
MAX_DIM="${FRAME_MAX_DIM:-1600}"

VIDEO="$(ls "$CAPTURE_DIR"/video.* 2>/dev/null | head -1 || true)"
if [[ -z "$VIDEO" ]]; then
  echo "ERROR: no video found in $CAPTURE_DIR" >&2
  exit 1
fi

command -v ffmpeg >/dev/null || { echo "ERROR: ffmpeg not installed" >&2; exit 1; }

mkdir -p "$OUT"
rm -f "$OUT"/frame_*.jpg

echo "[prepare_frames] $VIDEO -> $OUT (fps=$FPS max_dim=$MAX_DIM)"
ffmpeg -hide_banner -loglevel warning -y -i "$VIDEO" \
  -vf "fps=${FPS},scale='if(gt(iw,ih),min(iw,${MAX_DIM}),-2)':'if(gt(iw,ih),-2,min(ih,${MAX_DIM}))'" \
  -qscale:v 2 "$OUT/frame_%05d.jpg"

COUNT="$(ls "$OUT"/frame_*.jpg | wc -l)"
echo "[prepare_frames] extracted $COUNT frames"
if [[ "$COUNT" -lt 10 ]]; then
  echo "ERROR: too few frames ($COUNT) — record a longer capture" >&2
  exit 1
fi
