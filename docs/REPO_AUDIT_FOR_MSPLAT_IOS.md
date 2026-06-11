# Repository audit — msplat iOS pivot

Audit date: 2026-06-11. Repository: `YoelVirada/3d`.

## Current architecture (after pivot)

```
iPhone (SpatialCapture app)
  ├── Capture/     ARKit session, video + future frame/pose metadata
  ├── Dataset/     Local session layout on device (manifest.json, frames/, video.mov)
  ├── MsplatBridge/  Swift protocols only — no linked msplat binary yet
  ├── Training/    State + statistics models (no trainer)
  ├── Rendering/   Protocol only
  ├── Diagnostics/ Device / thermal / FPS placeholders
  └── Legacy/      Optional server upload client (feature-flagged, debug)
```

Product direction: **on-device 3D Gaussian Splatting research wrapper** targeting
[`rayanht/msplat`](https://github.com/rayanht/msplat) as the Metal training engine.
No GPU-host Mobile-GS pipeline in this repo anymore.

## Files / modules to keep

| Path | Role |
|------|------|
| `apps/ios-capture/` | Primary product — SwiftUI + ARKit capture shell |
| `apps/ios-capture/SpatialCapture/Capture/` | AR capture, intrinsics/pose types, `ARVideoRecorder` |
| `apps/ios-capture/SpatialCapture/Dataset/` | Local session model + on-disk layout |
| `apps/ios-capture/SpatialCapture/MsplatBridge/` | Integration protocols (trainer, dataset, export) |
| `apps/ios-capture/SpatialCapture/Training/` | Training state / stats models |
| `apps/ios-capture/SpatialCapture/Rendering/` | Renderer protocol |
| `apps/ios-capture/SpatialCapture/Diagnostics/` | Device diagnostics placeholders |
| `apps/ios-capture/SpatialCapture/Legacy/` | Server upload (off by default) |
| `scripts/open_ios_project.sh` | XcodeGen project generation |
| `scripts/verify_deps.sh` | iOS toolchain check |
| `data/captures/.gitkeep` | Optional local sample data slot (gitignored contents) |
| `docs/MSPLAT_IOS_PORT_AUDIT.md` | msplat iOS port questions + iPhone-first plan |

## Files / modules to deprecate

| Path | Notes |
|------|-------|
| `apps/ios-capture/SpatialCapture/Legacy/` | Remove once server path is fully abandoned |
| `UserDefaults` keys `legacyServer*` | Legacy upload settings |

## Files / modules removed (this cleanup)

| Path | Reason |
|------|--------|
| `server/capture-upload/` | GPU-host upload + Mobile-GS orchestration |
| `training/mobile-gs/` | FFmpeg → COLMAP → Mobile-GS scripts |
| `runtime/` | Mobile-GS decoder notes, ios-runtime-tbd stubs |
| `third_party/Mobile-GS/` | Never committed; clone via old `setup_env.sh` |
| `docs/ARCHITECTURE.md`, `CLEANUP_NOTES.md`, `RUNTIME_TBD.md` | Mobile-GS server architecture |
| `scripts/setup_env.sh` | CUDA / COLMAP / Mobile-GS conda setup |

## Files / modules to migrate (next)

| From | To | Work |
|------|-----|------|
| ARFrame in `ARCaptureView` | `CaptureSessionLayout` + `ImageStorage` | Persist frames, poses, intrinsics |
| Local session directory | msplat COLMAP loader | Export `images/` + `sparse/0/` or direct in-memory dataset |
| `MsplatBridge` protocols | `MsplatCore.xcframework` (iOS slice) | Link C API, metallib path on iOS |
| `Training/` models | msplat trainer callbacks | Wire `msplat_trainer_step` stats |
| `Rendering/` protocol | msplat `render_pose_to_buffer` | Inference before full training |

## Risks

1. **msplat is macOS-first today** — Swift package targets macOS 15 only; XCFramework build uses `xcrun -sdk macosx metal`. iOS requires new CMake/SDK slices and likely `#if TARGET_OS_IPHONE` guards.
2. **Memory** — Training holds millions of Gaussians on GPU; iPhone RAM and jetsam limits are much tighter than M-series Macs.
3. **Thermal** — Sustained Metal compute will throttle; need iteration budgets and pause/resume.
4. **Dataset size** — Full-resolution frame export from ARKit can exhaust storage quickly.
5. **Pose quality** — ARKit poses differ from COLMAP; msplat expects COLMAP-style cameras unless we adapt loaders.
6. **Metallib deployment** — iOS app must bundle `default.metallib` and call `msplat_set_metallib_path` (already in C API).
7. **C++/ObjC++ in app target** — XcodeGen app may need an embedded static lib or SPM binary target for msplat core.

## Suggested migration order

1. **Structured local capture** — Finish TODOs in `ARCaptureView` / `CaptureSessionLayout` (manifest + optional frames).
2. **COLMAP-compatible export** — Minimal `images/` + `sparse/0/` from ARKit poses for msplat smoke tests.
3. **msplat iOS build audit** — Fork or patch msplat: iOS metallib, XCFramework slices (`iphoneos` + `iphonesimulator`), lower default resolution / splat caps.
4. **Inference-first on iPhone** — Load PLY/checkpoint, `render_pose_to_buffer` only (smallest smoke test).
5. **Short training loop** — Few iterations, aggressive downscale, memory telemetry in `Diagnostics/`.
6. **Full training UI** — `Training/` state machine, export via `SplatAssetExporter`.
7. **Remove Legacy/** — When server path is no longer needed.
