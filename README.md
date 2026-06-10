# Mobile-GS Spatial Pipeline

iPhone capture + Mobile-GS backend training/compression. The client runtime is
**intentionally TBD** — this repo stops at the backend artifact.

```
iOS Capture ──upload──► capture-upload server
                              │
            FFmpeg frames → COLMAP dataset → Mobile-GS train/compress
                              │
                            comp.xz
                              │
                              ▼
                    runtime TBD (iPhone-native only)
```

The confirmed backend artifact is Mobile-GS **`comp.xz`**. Until an
iPhone-native runtime is chosen, the only end-to-end validation is
backend-side `render.py --decode` on the GPU host.

## Layout

| Path | Layer |
|------|-------|
| `apps/ios-capture/` | iOS capture app (ARKit assists capture only; no pose export) |
| `server/capture-upload/` | minimal upload server; starts the backend pipeline |
| `training/mobile-gs/` | FFmpeg frames → COLMAP dataset → Mobile-GS train → `comp.xz` |
| `third_party/Mobile-GS/` | Mobile-GS clone (training/compression source of truth) |
| `runtime/ios-runtime-tbd/` | runtime gap — not implemented, iPhone-native only |
| `runtime/mobile-gs-decoder/` | Mobile-GS CUDA decode notes (reference/inspection) |
| `docs/` | architecture, runtime status, cleanup notes |

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

## Active layers

1. **Capture** — `apps/ios-capture/`. Native iOS video recording; ARKit
   provides tracking-quality feedback only.
2. **Dataset preparation** — `prepare_frames.sh` (FFmpeg) and `run_colmap.sh`
   (COLMAP).
3. **Training/compression** — Mobile-GS train/compress scripts; output is
   `comp.xz`. Validate with `render.py --decode` on the backend.
4. **Runtime** — not implemented. See `runtime/ios-runtime-tbd/` and
   `docs/RUNTIME_TBD.md`.

Details: `docs/ARCHITECTURE.md` · runtime status: `docs/RUNTIME_TBD.md` ·
cleanup history: `docs/CLEANUP_NOTES.md`.
