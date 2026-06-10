# Mobile-GS training & compression

Dataset preparation and training/compression layer. Mobile-GS
([xiaobiaodu/Mobile-GS](https://github.com/xiaobiaodu/Mobile-GS)) is the
**source of truth** for training and compression — we only wrap its CLI.
The final artifact is the compressed asset Mobile-GS produces (`comp.xz`).

## Flow

```
data/captures/<scene>/video.mov
  → prepare_frames.sh          FFmpeg frame extraction
  → run_colmap.sh              COLMAP feature extract / match / sparse map
  → run_mobile_gs_train.sh     Mobile-GS training (CUDA GPU)
  → run_mobile_gs_compress.sh  Mobile-GS compression → outputs/<scene>/comp.xz
```

Each script takes the scene id as `$1` (or `SCENE_ID` env var) and is
idempotent per scene. The capture-upload server runs them in order.

## Layout per scene

```
training/mobile-gs/outputs/<scene>/
  dataset/
    images/            extracted frames (FFmpeg)
    sparse/0/          COLMAP sparse reconstruction
    database.db        COLMAP database
  model/               Mobile-GS training output
  comp.xz              final compressed asset
```

## Prerequisites

- FFmpeg, COLMAP on PATH
- conda env `mobile-gs` (python 3.11, torch 2.5.1 cu118) — `scripts/setup_env.sh`
- Mobile-GS clone at `third_party/Mobile-GS` with its requirements installed
- `tmc3` (MPEG GPCC) on PATH — required by Mobile-GS compression

## Manual run

```bash
bash training/mobile-gs/prepare_frames.sh my_scene
bash training/mobile-gs/run_colmap.sh my_scene
bash training/mobile-gs/run_mobile_gs_train.sh my_scene
bash training/mobile-gs/run_mobile_gs_compress.sh my_scene
ls -lh training/mobile-gs/outputs/my_scene/comp.xz
```
