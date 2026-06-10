# Spatial Capture (iOS)

Native iOS app for capturing object-scan videos. This is the **Capture** layer
of the Mobile-GS pipeline.

The app records video and uploads it to the capture-upload server. The server
runs FFmpeg → COLMAP → Mobile-GS training/compression on the GPU host and
produces a compressed asset (`comp.xz`). **No rendered frames are ever streamed
back to the phone** — the future native runtime downloads the compressed asset
and renders it locally.

## ARKit's role

ARKit is used **only to assist the capture itself**: live preview with
tracking-quality feedback (slow motion hints, tracking state) while recording.
It does **not** export camera poses, transforms, or AR packages of any kind.
Camera geometry is reconstructed server-side with COLMAP.

## Capture modes

| Mode | Output |
|------|--------|
| Guided Capture (AR-assisted) | `.mov` recorded from ARKit camera frames |
| Record Video (camera) | `.mov` from the system camera UI |
| Choose from Library | any existing video |

All modes upload a plain video file.

## Open in Xcode (from Git)

Source of truth: `apps/ios-capture/SpatialCapture/` (Swift + `Info.plist`).
The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
export IOS_DEVELOPMENT_TEAM=YOUR_TEAM_ID
export IOS_BUNDLE_ID=com.yourname.spatialcapture   # optional; default com.yoel.spatialcapture
bash scripts/open_ios_project.sh
```

Find your Team ID in [Apple Developer → Membership](https://developer.apple.com/account)
or Xcode → Settings → Accounts.

## Server setup

1. GPU host (WSL): `python server/capture-upload/app.py`
2. App server field: `http://<HOST-LAN-IP>:8787`

## API

- `POST /captures/{scene_id}` — multipart upload: `video` file + `metadata` JSON; starts the backend pipeline
- `GET /captures/{scene_id}/status` — pipeline status (`uploaded` / `running` / `completed` / `failed`) and final artifact path
