# Spatial Asset Compiler

Capture-first pipeline: **iPhone video → object-aware 3D spatial asset package**.

Setup is **manual and pinned** for reproducibility on WSL2 + RTX 2080 Ti (CUDA 12.4 / compute 7.5). Do not use old conda envs (`3dgs`, `maskgen`), old paths (`stable-3d`, `colmap-cuda`), or patched local Nerfstudio/gsplat experiments.

## Setup (run manually — in order)

```bash
conda create -n spatial-asset-clean python=3.11 -y
conda activate spatial-asset-clean

bash scripts/setup_third_party.sh --yes
bash scripts/setup_env.sh --yes
bash scripts/download_sam2_checkpoints.sh
bash scripts/setup_heavy_envs.sh --yes

bash scripts/verify_deps.sh
bash scripts/verify_deps.sh --full
# or:
bash scripts/doctor.sh
```

### What gets pinned

| Component | Pin |
|-----------|-----|
| Python | 3.11 |
| torch | 2.6.0+cu124 |
| torchvision | 0.21.0+cu124 |
| numpy | 1.26.x (`<2`) |
| OpenCV | opencv-python-headless==4.10.0.84 |
| nerfstudio | v1.1.5 (editable `third_party/nerfstudio`) |
| gsplat | **v1.4.0** (editable `third_party/gsplat`, `--no-build-isolation`) |

Nerfstudio v1.1.5 requires **gsplat==1.4.0** — not v1.5.x. See `third_party/versions.lock.json` and `constraints/main-cu124.txt`.

### Environments

| Env | Role |
|-----|------|
| `spatial-asset-clean` | Main pipeline: Nerfstudio, gsplat 1.4.0, SAM2, Open3D |
| `saga-lift` | Isolated heavy stage: SegAnyGAussians |
| `gaussian-grouping` | Isolated heavy stage: Gaussian Grouping fallback |
| `sugar-mesh` | Isolated heavy stage: SuGaR mesh |

Heavy-stage envs are **isolated** (legacy torch stacks), not “optional” in the product vision. Status: `logs/setup/heavy_envs_status.json`.

Requires: FFmpeg, COLMAP (`/usr/bin/colmap`), NVIDIA driver, Node 20+ for viewer.

## Proof modes

The **official proof** is **iPhone mobile-in-the-loop**: capture on device → upload to WSL server → server runs pipeline → iPhone opens web viewer → device render metrics POST back to the server. Evidence is written under `runs/{scene_id}/` (`events.jsonl`, `run_report.json`, `run_report.md`, `metrics/mobile_metrics.json`).

| Mode | Purpose |
|------|---------|
| **iPhone path** | End-to-end proof including upload + on-device render/load metrics |
| **curl upload path** | API check without Xcode; can upload only or upload + background pipeline |
| **Local debug video** | Fast iteration on WSL with a local file (no phone render metrics) |

### 1. iPhone mobile-in-the-loop (official proof)

**WSL (processing server):**

```bash
bash scripts/run_capture_server.sh
# optional LAN URLs for result links:
# export SAC_PUBLIC_BASE_URL=http://<PC-LAN-IP>:8787
# export SAC_VIEWER_BASE_URL=http://<PC-LAN-IP>:5173

cd apps/viewer-web && npm install && npm run dev -- --host
```

**Mac:** build `apps/capture-ios` in Xcode only (not the GPU pipeline).

**iPhone:** set server base URL to `http://<PC-LAN-IP>:8787`, record/upload video, poll run status, tap **Open Viewer** when complete. Safari loads the viewer with `run_id` + `api` query params; render metrics POST to `POST /runs/{run_id}/mobile-metrics`.

See [apps/capture-ios/README.md](apps/capture-ios/README.md) for LAN / port forwarding.

### 2. curl upload path

```bash
bash scripts/run_capture_server.sh
curl -sf -X POST "http://127.0.0.1:8787/captures/example" \
  -F "video=@/path/to/video.mov" \
  -F 'metadata={"device_model":"curl-test"}' \
  -F "start_pipeline=true" \
  -F "profile=dev"
# → scene_id, run_id, status_url

curl -s "http://127.0.0.1:8787/runs/<run_id>/status"
curl -s "http://127.0.0.1:8787/runs/<run_id>/result"
```

### 3. Local debug video path (debugging only)

```bash
bash scripts/run_capture_server.sh   # terminal 1
SAC_RUN_FULL_PIPELINE=1 bash scripts/run_dev_pipeline_from_video.sh example /path/to/video.mov   # terminal 2
```

Or run the pipeline CLI directly after a manual upload:

```bash
conda activate spatial-asset-clean
python -m spatial_asset_compiler.run --scene-id example --output exports/example
```

### View asset package (browser)

```bash
cd apps/viewer-web && npm run dev
```

Open: `http://localhost:5173/?package=http://127.0.0.1:8787/exports/example/manifest.json`

For mobile proof, use the `viewer_url` from `GET /runs/{run_id}/result` (includes `run_id` and `api` for auto metrics).

## Output layout

```
exports/{scene_id}/
  manifest.json
  objects.json
  benchmarks.json
  scene.ply
  frames/ reconstruction/ masks/ object_groups/ meshes/ viewer/
  mobile_benchmarks/
  logs/

runs/{scene_id}/          # per mobile-in-the-loop proof (when using capture server)
  events.jsonl
  run_report.json
  run_report.md
  stage_logs/
  metrics/mobile_metrics.json
```

## Profiles

| Profile | Use |
|---------|-----|
| `dev` | Faster iteration (fewer splat/SAGA iterations, vote fallback allowed) |
| `production` | Full quality; SAGA/GG required (no vote-only) |
| `mesh-full` | + SuGaR scene mesh attempt |

## Scripts

See [scripts/README.md](scripts/README.md) for what each script does, safety, and approval flags.

## Docs

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [ROADMAP.md](ROADMAP.md)
- [third_party/README.md](third_party/README.md)
- [research/README.md](research/README.md)
