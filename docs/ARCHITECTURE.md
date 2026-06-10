# Architecture

iPhone capture + Mobile-GS backend training/compression. The pipeline stops
at the compressed artifact; client runtime is intentionally TBD.

```
iOS Capture
        │  upload video
        ▼
capture-upload server
        │  background task
        ▼
FFmpeg frame extraction ──► COLMAP dataset ──► Mobile-GS train/compress ──► comp.xz
                                                                               │
                                                                               ▼
                                                                    runtime TBD (iPhone-native only)
```

The architecture **explicitly stops at `comp.xz`**. No client renderer is
implemented in this repository yet.

## Layer 1 — Capture (`apps/ios-capture/`)

- Native iOS video capture only.
- ARKit assists the capture itself (live tracking-quality feedback, motion
  hints) — it does **not** export camera poses.
- Output: a plain video file uploaded to the server.

## Layer 2 — Dataset preparation (`training/mobile-gs/`)

- `prepare_frames.sh` — FFmpeg extracts frames from the uploaded video.
- `run_colmap.sh` — COLMAP (feature extraction, matching, sparse mapping)
  produces the `images/ + sparse/0/` dataset Mobile-GS expects.
- COLMAP is a direct dependency; there is no wrapper framework.

## Layer 3 — Training & compression (`training/mobile-gs/`, `third_party/Mobile-GS`)

- Mobile-GS ([xiaobiaodu/Mobile-GS](https://github.com/xiaobiaodu/Mobile-GS))
  is the source of truth for training and compression.
- `run_mobile_gs_train.sh` / `run_mobile_gs_compress.sh` wrap its CLI.
- The output artifact is exactly what Mobile-GS emits: **`comp.xz`**.
- Backend validation: `render.py --decode` inside Mobile-GS renders from
  `comp.xz` on the GPU host (identical to the PLY path).

## Layer 4 — Runtime (`runtime/`) — **not implemented**

- `runtime/ios-runtime-tbd/` — documented gap; iPhone-native runtime undecided.
- `runtime/mobile-gs-decoder/` — notes on Mobile-GS CUDA decode behavior
  (reference/inspection only; not a client renderer).
- Product direction is iPhone-first. No Vulkan, MoltenVK, 3DGS.cpp, or
  Android-first runtime work lives in this repo.

## Server (`server/capture-upload/`)

Minimal FastAPI app: accepts the video, stores it under `data/captures/`,
runs the layer-2/3 scripts as a background task, reports status, and serves
the finished `comp.xz`.
