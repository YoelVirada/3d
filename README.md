# Mobile-GS Spatial Pipeline

Capture an object with an iPhone → train a compressed Gaussian-splat asset
with Mobile-GS → render it natively on device.

```
iOS capture app ──upload──► capture-upload server
                                  │
                FFmpeg frames → COLMAP dataset → Mobile-GS train/compress
                                  │
                                comp.xz
                                  │ download
                                  ▼
                native runtime: decode → GPU buffers → local render
```

The server never streams rendered frames. It produces one artifact — the
compressed Mobile-GS asset (`comp.xz`) — and the client runtime decodes and
renders it locally.

## Layout

| Path | Layer |
|------|-------|
| `apps/ios-capture/` | iOS capture app (ARKit assists capture only; no pose export) |
| `server/capture-upload/` | minimal upload server; starts the backend pipeline |
| `training/mobile-gs/` | FFmpeg frames → COLMAP dataset → Mobile-GS train → `comp.xz` |
| `runtime/mobile-gs-decoder/` | decoder research; Mobile-GS CUDA code as reference |
| `runtime/vulkan-renderer/` | native renderer prototype based on 3DGS.cpp |
| `third_party/Mobile-GS/` | Mobile-GS clone (training/compression source of truth) |
| `docs/` | architecture, runtime plan, cleanup notes |

## Quick start

```bash
# 1. Backend environment (FFmpeg, COLMAP, Mobile-GS + CUDA PyTorch env)
bash scripts/setup_env.sh

# 2. Verify
bash scripts/verify_deps.sh

# 3. Run the upload server (GPU host)
python server/capture-upload/app.py

# 4. iOS app (on a Mac)
brew install xcodegen
export IOS_DEVELOPMENT_TEAM=YOUR_TEAM_ID
bash scripts/open_ios_project.sh
```

Capture a video in the app and upload; the server runs:
`prepare_frames.sh` → `run_colmap.sh` → `run_mobile_gs_train.sh` →
`run_mobile_gs_compress.sh`, ending with
`training/mobile-gs/outputs/<scene>/comp.xz`.

## The four layers

1. **Capture** — native iOS video recording. ARKit provides live
   tracking-quality feedback to help the user capture well; it does not
   extract camera poses.
2. **Dataset preparation** — FFmpeg extracts frames; COLMAP builds the
   `images/ + sparse/0/` dataset Mobile-GS expects. Direct dependencies, no
   wrappers.
3. **Training/compression** — [Mobile-GS](https://github.com/xiaobiaodu/Mobile-GS)
   is the source of truth. Output is exactly its compressed artifact,
   `comp.xz`.
4. **Native runtime research** — the Mobile-GS CUDA decoder is the behavioral
   reference; [3DGS.cpp](https://github.com/shg8/3DGS.cpp) is the initial
   Vulkan renderer base. The renderer work replaces global depth sorting /
   alpha blending with a depth-aware order-independent (SortFreeGS-style)
   pipeline. On iOS, Vulkan is not native — research uses MoltenVK, with a
   Metal port as the production path.

Details: `docs/ARCHITECTURE.md` · roadmap: `docs/MOBILE_GS_RUNTIME_PLAN.md` ·
what was removed and why: `docs/CLEANUP_NOTES.md`.
