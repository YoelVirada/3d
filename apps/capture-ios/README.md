# Spatial Capture (iOS)

Capture app for **mobile-in-the-loop** proof with **ARKit pose capture as the default path**.

Mac/Xcode builds this app only. **GPU processing runs on the WSL server** (`scripts/run_capture_server.sh`).

## Capture modes

| Mode | Upload | Server path |
|------|--------|-------------|
| **AR Capture (default)** | `ar_capture.zip` | ARKit poses → `transforms.json`, **COLMAP skipped** |
| **Video (legacy)** | `video.mov` | FFmpeg + COLMAP |

## Features

- Configurable API base URL (persisted)
- ARSession world tracking @ ~3 Hz with pose + intrinsics per frame
- Legacy video record / library pick
- Upload + poll pipeline status
- Open viewer URL with `run_id` for render metrics

## LAN setup

1. WSL: `bash scripts/run_capture_server.sh` and `cd apps/viewer-web && npm run dev -- --host`
2. PC LAN IP + port forward 8787 and 5173 to WSL if needed
3. `export SAC_PUBLIC_BASE_URL=http://<PC-LAN-IP>:8787`
4. App server field: `http://<PC-LAN-IP>:8787`

## AR package layout (inside zip)

```
capture.json          capture_mode=arkit
ar/manifest.json
ar/poses.json
ar/frames/frame_*.jpg
```

## Pre-training sanity checks (server)

After AR ingest/reconstruction, inspect on WSL:

- `exports/{scene_id}/reconstruction/arkit_pose_debug.json`
- `exports/{scene_id}/reconstruction/first_pose_debug.json`
- `exports/{scene_id}/reconstruction/arkit_frustum_preview.html`

## API

- `POST /captures/{scene_id}` with `ar_package` (zip) or `video`
- `GET /runs/{run_id}/status` | `/result`
- `POST /runs/{run_id}/mobile-metrics`

Android/ARCore: schema-ready, not implemented in v1.
