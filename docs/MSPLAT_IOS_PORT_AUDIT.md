# msplat iOS port audit

Reference: [`rayanht/msplat`](https://github.com/rayanht/msplat) (Metal 3DGS training engine for Apple Silicon).

This document lists **questions we must answer before iOS support** and outlines an
**iPhone-first** conversion (not “build on macOS as-is and hope it links”).

## msplat architecture (public)

| Component | Location | Notes |
|-----------|----------|-------|
| Metal kernels | `core/metal/msplat_metal.metal` | 44 fused compute kernels (project, sort, rasterize, SSIM, Adam, densify) |
| ObjC++ Metal bridge | `core/metal/msplat_metal.mm`, `core/src/msplat_api.mm` | MTLDevice, command queues, pipeline states |
| C++ core | `core/src/model.cpp`, loaders, SSIM | Training loop, dataset loaders |
| C API | `core/include/msplat_c_api.h` | Swift interop surface |
| Swift package | `swift/Package.swift` | Wraps `MsplatCore.xcframework` + `default.metallib` resource |
| Build | `CMakeLists.txt`, `scripts/build-xcframework.sh` | Static `libmsplat_core.a` + headers |

Swift package today:

```swift
platforms: [.macOS(.v15)]  // no iOS
```

Metal compile today (CMake):

```bash
xcrun -sdk macosx metal ...   # macOS SDK only
```

XCFramework script builds a **single** static library — no `iphoneos` / `iphonesimulator` slices.

## Questions to answer before iOS support

### Build / packaging

| # | Question | How to verify | Current hypothesis |
|---|----------|---------------|-------------------|
| 1 | Does the XCFramework include iOS targets or only macOS? | Inspect `MsplatCore.xcframework/Info.plist` slices | **macOS only** — script uses one `libmsplat_core.a` |
| 2 | Can Metal kernels compile with `xcrun -sdk iphoneos metal`? | Cross-compile metallib per SDK | Likely yes (same Metal language); tile sizes may need tuning |
| 3 | Are ObjC++ / C++ layers compatible with iOS app targets? | Add iOS slice to CMake, link into test app | Yes with `-std=c++17`, Foundation/Metal frameworks |
| 4 | How is `default.metallib` loaded on iOS? | `msplat_set_metallib_path` + bundle resource | C API already supports explicit path; Swift uses `Bundle.module` on macOS |

### Runtime / API availability

| # | Question | Notes |
|---|----------|-------|
| 5 | Are Metal Performance Shaders (MPS) paths used in ways unavailable on iOS? | CMake links `MetalPerformanceShaders`; `USE_MPS` defined — verify iOS GPU feature set |
| 6 | Do kernels assume desktop GPU memory (unified memory size, threadgroup limits)? | iPhone GPUs have lower threadgroup memory; 16×16 tiles × 2048 Gaussians per tile is aggressive |
| 7 | Command queue / buffer pooling — any macOS-only APIs? | Audit `msplat_metal.mm` for `NSProcessInfo`, file paths, pthread assumptions |
| 8 | Thread pool / `pthread` usage — safe on iOS? | CLI links `pthread`; check background QoS and main-thread rules |

### Dataset / filesystem

| # | Question | Notes |
|---|----------|-------|
| 9 | Does msplat load macOS-specific filesystem paths or formats only? | Loaders: COLMAP, Nerfstudio, Polycam, PLY — path-based `fopen` style; need sandbox-friendly URLs |
| 10 | Can dataset load from app sandbox (`Documents/captures/...`)? | Pass POSIX path from `CaptureSessionLayout` |
| 11 | Image I/O via ImageIO/CoreGraphics — HEIC/JPEG from ARKit? | `image_io.cpp` — confirm formats |

### Training vs inference

| # | Question | Notes |
|---|----------|-------|
| 12 | Can we run inference/render/export on iOS **before** training? | `msplat_trainer_render_pose_to_buffer` — load checkpoint or PLY, render one view |
| 13 | Minimum viable training on iPhone? | Few images, heavy downscale (`downscaleFactor`), low `iterations`, cap densification |
| 14 | Checkpoint / PLY export to Files app? | `export_ply`, `export_splat`, `save_checkpoint` write to paths |

### Smoke test definition

| # | Question | Proposed smallest iPhone smoke test |
|---|----------|-----------------------------------|
| 15 | What is the smallest smoke test? | (1) Bundle pre-trained tiny PLY + metallib, (2) one `render_pose_to_buffer` call, (3) display RGBA in SwiftUI — **no training** |

## iPhone-first conversion — is it possible?

**Yes, with deliberate fork/patch work in msplat (upstream or `third_party/msplat`).**
The engine is already Metal-native; the gap is **packaging and product assumptions**, not CUDA.

### What “iPhone-first” means

- Primary CMake/Xcode targets: `iphoneos` + `iphonesimulator` (+ optional macOS for dev).
- Default configs tuned for phone: smaller images, fewer iterations, lower splat counts.
- Swift package platforms: `.iOS(.v16)` (or `.v17`) alongside or instead of macOS.
- App integrates via SPM binary target or vendored XCFramework in this repo.

### Where to change in msplat (not in this repo yet)

| Area | File(s) | Change |
|------|---------|--------|
| SDK selection | `CMakeLists.txt` | Replace `xcrun -sdk macosx` with per-platform metallib rules; `CMAKE_OSX_SYSROOT` for iOS |
| XCFramework | `scripts/build-xcframework.sh` | Build `libmsplat_core.a` for device + sim; `xcodebuild -create-xcframework` with both slices |
| Swift package | `swift/Package.swift` | Add `.iOS(.v16)`, conditional resources for metallib per platform |
| Memory / caps | `core/include/msplat_c_api.h`, `MsplatConfig` | Phone presets: `downscaleFactor`, `iterations`, densify thresholds |
| Tile / kernel limits | `core/metal/msplat_metal.metal` | Possibly reduce max Gaussians per tile on A-series GPUs |
| MPS usage | `msplat_metal.mm`, `model.cpp` | Fallback paths if MPS op missing on older iPhones |
| Dataset loaders | `core/src/loaders/*` | Sandbox paths, optional in-memory dataset from app buffers (future) |
| App bridge | This repo `MsplatBridge/` | Implement protocols wrapping C API; set metallib path from app bundle |

### Recommended path (avoid “macOS as-is”)

1. **Do not** depend on pip/macOS CLI for the product loop.
2. **Clone msplat** into `third_party/msplat` (submodule) with iOS CMake patches.
3. **Ship inference first** — proves metallib + linking + memory on device.
4. **Add training** with hard caps and thermal monitoring from `Diagnostics/`.
5. Keep macOS build only as a **dev convenience** for faster iteration, not the primary target.

## Open items for this repository

- [ ] Add `third_party/msplat` submodule when fork with iOS CMake is ready
- [ ] Implement COLMAP export from `CaptureSessionManifest`
- [ ] Wire `MsplatBridge` to real C API after first iOS XCFramework build
- [ ] Document device matrix (minimum iPhone model, iOS version)

See also: `docs/REPO_AUDIT_FOR_MSPLAT_IOS.md`.
