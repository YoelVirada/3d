# Spatial Capture (iOS)

Capture app for **mobile-in-the-loop** proof: record → upload → poll pipeline → open web viewer → auto-report render metrics.

Mac/Xcode builds this app only. **GPU processing runs on the WSL server** (`scripts/run_capture_server.sh`).

## Features

- Configurable API base URL (persisted)
- Record video (`AVCaptureSession`) or pick from library
- Upload with progress UI
- Poll `GET /runs/{run_id}/status` until complete
- Open **viewer URL** in Safari (includes `run_id` + `api` for metrics)
- POST upload telemetry to `POST /runs/{run_id}/mobile-metrics`

## LAN setup (local proof)

1. On WSL, start server and viewer:
   ```bash
   bash scripts/run_capture_server.sh
   cd apps/viewer-web && npm run dev -- --host
   ```
2. Find your PC LAN IP (Windows `ipconfig`, or route to WSL).
3. Forward port **8787** (and **5173** for viewer) from Windows to WSL if needed:
   ```powershell
   netsh interface portproxy add v4tov4 listenport=8787 listenaddress=0.0.0.0 connectport=8787 connectaddress=<wsl-ip>
   netsh interface portproxy add v4tov4 listenport=5173 listenaddress=0.0.0.0 connectport=5173 connectaddress=<wsl-ip>
   ```
4. On WSL, set public URLs so result links work on the phone:
   ```bash
   export SAC_PUBLIC_BASE_URL=http://<PC-LAN-IP>:8787
   export SAC_VIEWER_BASE_URL=http://<PC-LAN-IP>:5173
   ```
5. In the app **Server** field: `http://<PC-LAN-IP>:8787` (not `localhost`).
6. Enable **Local Network** in `Info.plist` (`NSAllowsLocalNetworking`).

## Xcode

1. Open / create project from `SpatialCapture/` sources.
2. Add `RunAPI.swift`, `UploadService.swift`, etc. to target.
3. Set Team + bundle ID.
4. Build to a physical iPhone (Simulator cannot measure real upload/render on LAN the same way).

## Evidence on server

After a full proof:

```
data/captures/{scene_id}/video.*
exports/{scene_id}/manifest.json
runs/{scene_id}/
  events.jsonl
  run_report.json
  run_report.md
  metrics/mobile_metrics.json
```

## API (used by app)

- `POST /captures/{scene_id}` — multipart `video`, `metadata`, `start_pipeline=true`
- `GET /runs/{run_id}/status`
- `GET /runs/{run_id}/result`
- `POST /runs/{run_id}/mobile-metrics`

Native Metal viewer is **not** implemented; Safari uses `apps/viewer-web`.
