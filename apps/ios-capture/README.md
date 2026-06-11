# Spatial Capture (iOS)

Native iPhone capture shell for on-device 3DGS research (msplat / PocketGS style experiments).

## Modules

| Folder | Role |
|--------|------|
| `App/` | SwiftUI shell, settings |
| `Capture/` | ARKit capture, intrinsics/pose types, video recorder |
| `Dataset/` | Local session layout (`Documents/captures/<id>/`) |
| `MsplatBridge/` | Trainer/dataset/export protocols (no binary yet) |
| `Training/` | Training state and statistics models |
| `Rendering/` | Renderer protocol |
| `Diagnostics/` | Device / thermal / performance placeholders |
| `Legacy/` | Optional server upload (off by default) |

## Open in Xcode

```bash
brew install xcodegen
export IOS_DEVELOPMENT_TEAM=YOUR_TEAM_ID
bash ../../scripts/open_ios_project.sh
```

## Local session layout (target)

```
Documents/captures/<sessionId>/
  manifest.json
  video.mov
  intrinsics.json      # TODO
  frames/              # TODO
    frame_000001.jpg
```

COLMAP / msplat export paths are documented in `Dataset/CaptureSessionLayout.swift`.
