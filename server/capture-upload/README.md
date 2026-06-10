# capture-upload server

Minimal FastAPI server. Its only jobs:

1. Receive a captured video from the iOS app (`POST /captures/{scene_id}`).
2. Store it under `data/captures/<scene_id>/`.
3. Start the Mobile-GS backend pipeline as a background task
   (`training/mobile-gs/*.sh` in order: frames → COLMAP → train → compress).
4. Report status (`GET /captures/{scene_id}/status`).
5. Serve the final compressed asset (`GET /captures/{scene_id}/asset`).

It does **not** render anything and never streams frames to the client.
The deliverable is a compressed Mobile-GS asset (`comp.xz`). Client-side
runtime is intentionally TBD — iPhone-native only.

## Run

```bash
pip install fastapi uvicorn python-multipart
python server/capture-upload/app.py        # listens on 0.0.0.0:8787
```

## API

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/captures/{scene_id}` | multipart `video` + `metadata` JSON; starts pipeline |
| GET | `/captures/{scene_id}/status` | `uploaded` / `running` / `failed` / `completed` + stage |
| GET | `/captures/{scene_id}/asset` | download `comp.xz` when completed |

Pipeline logs: `logs/capture-upload/<scene_id>.log`.
