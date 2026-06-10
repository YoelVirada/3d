# Architecture

Mobile-GS-centric pipeline. Four layers, one artifact.

```
iOS capture app (video)
        │  upload
        ▼
capture-upload server
        │  background task
        ▼
FFmpeg frame extraction ──► COLMAP dataset ──► Mobile-GS train ──► comp.xz
                                                                     │
                                                                     ▼
                                              native runtime (decode + render on device)
```

**Hard rule:** the server never streams rendered frames to the client. It
produces a compressed Mobile-GS asset; the client runtime loads it, decodes
it, buffers it to the GPU, and renders locally.

## Layer 1 — Capture (`apps/ios-capture/`)

- Native iOS video capture only.
- ARKit assists the capture itself (live tracking-quality feedback, motion
  hints) — it does **not** export camera poses. There is no
  ARKit-to-transforms path.
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
  No other runtime formats are produced.

## Layer 4 — Native runtime research (`runtime/`)

- `runtime/mobile-gs-decoder/` — the Mobile-GS CUDA code is the reference for
  decode/render behavior; goal is a standalone decoder from `comp.xz` to GPU
  buffers.
- `runtime/vulkan-renderer/` — [3DGS.cpp](https://github.com/shg8/3DGS.cpp)
  is the initial Vulkan/C++ renderer base. The core work is replacing its
  depth sort + alpha blend with a Mobile-GS/SortFreeGS-style depth-aware
  order-independent pipeline.
- iOS note: Vulkan is **not** native on iOS — research runs through MoltenVK;
  the production path is a future Metal port.
- Final packaging target: a native runtime library, not a web viewer.

## Server (`server/capture-upload/`)

Minimal FastAPI app: accepts the video, stores it under `data/captures/`,
runs the layer-2/3 scripts as a background task, reports status, and serves
the finished `comp.xz`.
