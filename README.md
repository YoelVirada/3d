# 3DGS Capture — iPhone research wrapper

Native 3DGS research wrapper for iPhone for msplat/PocketGS style on-device training experiments.

The app captures spatial video (and future structured frame/pose metadata) locally on the device.
Training and rendering are **not implemented yet** — Swift protocols and audit docs define the
path to integrating [`rayanht/msplat`](https://github.com/rayanht/msplat) as the Metal engine.

```
iPhone SpatialCapture app
  Capture (ARKit + camera) → local session (manifest, video, future frames/poses)
  MsplatBridge (protocols)   → future msplat XCFramework on iOS
  Training / Rendering       → planned on-device experiments
```

## Layout

| Path | Purpose |
|------|---------|
| `apps/ios-capture/` | iOS app (XcodeGen) — primary codebase |
| `docs/REPO_AUDIT_FOR_MSPLAT_IOS.md` | Repo audit, keep/deprecate/migrate |
| `docs/MSPLAT_IOS_PORT_AUDIT.md` | msplat iOS port questions and iPhone-first plan |
| `scripts/open_ios_project.sh` | Generate and open Xcode project |
| `scripts/verify_deps.sh` | Check XcodeGen / Xcode (macOS) |

## Quick start (Mac + iPhone)

```bash
brew install xcodegen
export IOS_DEVELOPMENT_TEAM=YOUR_TEAM_ID
bash scripts/verify_deps.sh
bash scripts/open_ios_project.sh
```

Build and run `SpatialCaptureRunner` on a physical iPhone (ARKit requires a device).

### Capture modes

| Mode | Output today |
|------|----------------|
| Guided Capture (AR-assisted) | `.mov` in temp; local session export TODO |
| Record Video | `.mov` from system camera |
| Library picker | existing video file |

Legacy GPU-server upload is hidden behind the **Legacy upload** toggle (debug only).

## msplat integration status

- Swift protocols in `apps/ios-capture/SpatialCapture/MsplatBridge/`
- No msplat binary linked yet
- See `docs/MSPLAT_IOS_PORT_AUDIT.md` for iPhone-first port plan

## Removed (previous direction)

The Mobile-GS GPU-host pipeline (upload server, FFmpeg, COLMAP, CUDA training, `comp.xz`)
has been removed from this repository. Historical context is summarized in the repo audit doc.
