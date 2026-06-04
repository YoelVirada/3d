# Scripts

Lifecycle for the Spatial Asset Compiler. Eight scripts + this guide.

## Quick reference

| Script | Safe to re-run? | Changes environment? | Typical duration |
|--------|-----------------|----------------------|------------------|
| `verify_deps.sh` | Yes | No | Seconds |
| `doctor.sh` | Yes | No | Seconds |
| `download_sam2_checkpoints.sh` | Yes (skips existing) | No (disk only) | Minutes |
| `setup_third_party.sh` | Only with approval | No conda; **git checkout** in `third_party/` | Minutes |
| `setup_env.sh` | Only with approval | **Yes — `spatial-asset-clean`** | 10–30+ min |
| `setup_heavy_envs.sh` | Only with approval | **Yes — `saga-lift`, `gaussian-grouping`, `sugar-mesh`** | 30+ min |
| `run_capture_server.sh` | Yes | Activates main env only | Until stopped |
| `run_dev_pipeline_from_video.sh` | Only with approval | Activates main env; **full GPU pipeline** | Hours |

## One-line purpose

- **`verify_deps.sh`** — Is the environment ready? (read-only)
- **`doctor.sh`** — Run default + full verify and summarize
- **`setup_third_party.sh`** — Fetch/sync external repos from `versions.lock.json`
- **`setup_env.sh`** — Build the main `spatial-asset-clean` stack
- **`download_sam2_checkpoints.sh`** — Download SAM2 weights into `third_party/checkpoints/sam2/`
- **`setup_heavy_envs.sh`** — Build isolated heavy research envs (SAGA, Gaussian Grouping, SuGaR)
- **`run_capture_server.sh`** — Local API for iPhone capture upload
- **`run_dev_pipeline_from_video.sh`** — Upload a video and run the full **dev** pipeline

---

## Testing

### `verify_deps.sh`

Checks what is installed; does not install, change, or remove anything.

```bash
bash scripts/verify_deps.sh          # main env (spatial-asset-clean)
bash scripts/verify_deps.sh --full   # + SAM2 ckpts, heavy envs, viewer
```

### `doctor.sh`

Wrapper: runs both verify modes and prints PASS/FAIL with next-step hints.

```bash
bash scripts/doctor.sh
```

---

## Downloads

### `download_sam2_checkpoints.sh`

Downloads large SAM2 `.pt` files; verifies non-empty. No pip/conda.

```bash
bash scripts/download_sam2_checkpoints.sh
```

---

## Third-party code (git only)

### `setup_third_party.sh`

Clones or syncs: nerfstudio, gsplat (forced **v1.4.0**), sam2, SegAnyGAussians, gaussian-grouping, SuGaR.

Does **not** install Python packages. Can **move git checkouts** and discard uncommitted changes under `third_party/`.

```bash
bash scripts/setup_third_party.sh --yes
# or:
SAC_ALLOW_THIRD_PARTY_SYNC=1 bash scripts/setup_third_party.sh
```

---

## Main environment

### `setup_env.sh`

Prepares **`spatial-asset-clean`**: torch 2.6+cu124, nerfstudio/gsplat/sam2 editable, opencv headless, project editable, `pip check`.

**Most sensitive script** — reinstalls the main stack. Requires explicit approval:

```bash
bash scripts/setup_env.sh --yes
# or:
SAC_ALLOW_MAIN_ENV_SETUP=1 bash scripts/setup_env.sh
```

Prerequisites: conda env exists (Python 3.11), `setup_third_party.sh` done.

---

## Heavy isolated environments

### `setup_heavy_envs.sh`

Creates/updates **`saga-lift`**, **`gaussian-grouping`**, **`sugar-mesh`** only (legacy torch stacks; CUDA extension builds; SuGaR `install.py`).

Does **not** modify `spatial-asset-clean` (uses `conda run`).

Part of the product vision — technically isolated, not optional.

```bash
bash scripts/setup_heavy_envs.sh --yes
# or:
SAC_ALLOW_HEAVY_ENV_SETUP=1 bash scripts/setup_heavy_envs.sh
```

Status: `logs/setup/heavy_envs_status.json`

---

## Runtime

### `run_capture_server.sh`

Local proof runner: upload, background pipeline, run status, static exports, mobile metrics.

```bash
bash scripts/run_capture_server.sh
# iPhone LAN (optional):
# export SAC_PUBLIC_BASE_URL=http://192.168.x.x:8787
# export SAC_VIEWER_BASE_URL=http://192.168.x.x:5173
```

| Endpoint | Purpose |
|----------|---------|
| `POST /captures/{scene_id}` | Upload video + metadata; returns `run_id`; starts pipeline |
| `GET /runs/{run_id}/status` | Stage + elapsed time |
| `GET /runs/{run_id}/result` | `manifest_url`, `viewer_url`, `report_url` when done |
| `POST /runs/{run_id}/mobile-metrics` | iPhone / viewer render telemetry |
| `GET /exports/...` | Static asset package for phone viewer |

**Proof modes:** iPhone app (official) · curl (API test) · `run_dev_pipeline_from_video.sh` (local debug only). See root [README.md](../README.md).

### `run_dev_pipeline_from_video.sh`

Upload via curl, then `python -m spatial_asset_compiler.run --profile dev` (all stages).

**Not a toy example** — real GPU work. Requires approval:

```bash
# terminal 1
bash scripts/run_capture_server.sh

# terminal 2
SAC_RUN_FULL_PIPELINE=1 bash scripts/run_dev_pipeline_from_video.sh example /path/to/video.mov
```

Production-style run (after capture package exists):

```bash
conda activate spatial-asset-clean
python -m spatial_asset_compiler.run --scene-id <id> --output exports/<id>
```

---

## Recommended setup order (new machine)

```bash
conda create -n spatial-asset-clean python=3.11 -y
conda activate spatial-asset-clean

bash scripts/setup_third_party.sh --yes
bash scripts/setup_env.sh --yes
bash scripts/download_sam2_checkpoints.sh
bash scripts/setup_heavy_envs.sh --yes

bash scripts/verify_deps.sh
bash scripts/verify_deps.sh --full
# or: bash scripts/doctor.sh

cd apps/viewer-web && npm install   # for --full viewer check
```

---

## What these scripts do **not** do

- Delete conda envs
- Touch legacy envs (`3dgs`, `maskgen`) — `verify_deps.sh` only warns if they appear on `PATH`
- Auto-run setup when you start the capture server or pipeline
