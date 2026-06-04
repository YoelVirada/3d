#!/usr/bin/env bash
# Download SAM2.1 checkpoints. Fails on missing or empty files.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CKPT="$ROOT/third_party/checkpoints/sam2"
mkdir -p "$CKPT"

MIN_BYTES=1000000

download() {
  local url="$1"
  local out="$2"
  if [[ -f "$out" ]] && [[ "$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")" -ge "$MIN_BYTES" ]]; then
    echo "OK exists: $out"
    return 0
  fi
  echo "Downloading: $out"
  local tmp="${out}.partial"
  rm -f "$tmp"
  if command -v wget &>/dev/null; then
    wget -q -O "$tmp" "$url"
  elif command -v curl &>/dev/null; then
    curl -fsSL -o "$tmp" "$url"
  else
    echo "ERROR: wget or curl required"
    exit 1
  fi
  if [[ ! -s "$tmp" ]]; then
    echo "ERROR: download empty: $out"
    rm -f "$tmp"
    exit 1
  fi
  mv "$tmp" "$out"
  echo "OK saved: $out ($(stat -c%s "$out" 2>/dev/null || stat -f%z "$out") bytes)"
}

download \
  "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_small.pt" \
  "$CKPT/sam2.1_hiera_small.pt"

download \
  "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_base_plus.pt" \
  "$CKPT/sam2.1_hiera_base_plus.pt"

echo "SAM2 checkpoints ready:"
ls -la "$CKPT"/*.pt
