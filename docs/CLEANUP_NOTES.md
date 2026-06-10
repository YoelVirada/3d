# Cleanup notes (hard fork)

This repository was hard-forked from a multi-tool Gaussian-splatting pipeline
to a Mobile-GS-centric architecture. The old stack was removed entirely — no
compatibility shims, no optional legacy paths, no dead folders.

## Removed

**Reconstruction / training stack**
- Nerfstudio integration (`ns-process-data`, `ns-train splatfacto`,
  `ns-export gaussian-splat`) and the gsplat pipeline
- The entire `spatial_asset_compiler/` Python package (pipeline stages,
  manifest/benchmark compiler, capture server, ARKit pose ingestion,
  ARKit-to-transforms conversion)

**Segmentation / object lifting**
- SAM2 (+ checkpoint download script)
- SAGA / SegAnyGAussians, Gaussian Grouping, vote backup logic

**Mesh**
- Open3D mesh pipeline, SuGaR

**Specialized pipelines**
- LMG pipeline, MILo

**Viewer / runtime assets**
- PlayCanvas web viewer, `@playcanvas/splat-transform` (`tools/runtime/`)
- `@mkkellogg/gaussian-splats-3d` viewer (`apps/viewer-web/`)
- SOG export, SPZ, PLY runtime preview, GLB + SOG packaging

**Environments / scripts / third-party**
- Conda envs: `saga-lift`, `gaussian-grouping`, `sugar-mesh`
- `setup_heavy_envs.sh`, `download_sam2_checkpoints.sh`,
  `setup_runtime_tools.sh`, `setup_third_party.sh`, `doctor.sh`,
  `run_dev_pipeline_from_video.sh`, `run_capture_server.sh`
- Third-party clones: nerfstudio, gsplat, sam2, SegAnyGAussians,
  gaussian-grouping, SuGaR, LMG, PlayCanvas tooling
- Old tests (ARKit pose filtering / transforms), `pyproject.toml` packaging,
  pip constraints, env reports

## Kept (repurposed where noted)

- `apps/ios-capture/` (was `apps/capture-ios/`) — native SpatialCapture app +
  XcodeGen `project.yml`. **ARKit repurposed:** capture assistance only
  (tracking-quality feedback during recording); all pose
  extraction/export code deleted.
- Capture upload concept — rewritten from scratch as
  `server/capture-upload/app.py` (upload video + start backend task only).
- FFmpeg — video→frames preprocessing only.
- COLMAP — now the single dataset-preparation dependency (no wrapper).
- `scripts/open_ios_project.sh`, `scripts/setup_env.sh`,
  `scripts/verify_deps.sh` — rewritten for the new stack.

## Second cleanup (post-fork)

- Removed `runtime/vulkan-renderer/` and all 3DGS.cpp / Vulkan / MoltenVK /
  Android-first runtime scaffolding.
- Removed `SETUP_RUNTIME` / `CHECK_RUNTIME` script flags (they only cloned or
  verified 3DGS.cpp).
- Replaced `docs/MOBILE_GS_RUNTIME_PLAN.md` with `docs/RUNTIME_TBD.md`.
- Added `runtime/README.md` and `runtime/ios-runtime-tbd/` as a documented,
  intentionally empty runtime gap (iPhone-native only; no renderer scaffold).

## Added

See `docs/ARCHITECTURE.md` for the active layers and `docs/RUNTIME_TBD.md`
for the paused runtime status.
