# Runtime research — paused

Client-side runtime work is **paused** until we choose an iPhone-native
rendering approach.

## Current state

The repository has three active backend/capture layers and one explicit gap:

| Layer | Location | Status |
|-------|----------|--------|
| Capture | `apps/ios-capture/` | Active |
| Dataset preparation | `training/mobile-gs/prepare_frames.sh`, `run_colmap.sh` | Active |
| Training/compression | `training/mobile-gs/run_mobile_gs_train.sh`, `run_mobile_gs_compress.sh` | Active |
| Runtime | `runtime/ios-runtime-tbd/` | **Not implemented** |

The confirmed backend artifact is Mobile-GS **`comp.xz`**.

## End-to-end validation (today)

Until a runtime exists, validate on the GPU host only:

```bash
cd third_party/Mobile-GS
python render.py -s <colmap_dataset> -m <model_path> --decode
```

`--decode` renders from the compressed file instead of the PLY; results should
match. This is the ground-truth decode/render behavior to study in
`runtime/mobile-gs-decoder/`.

## Abandoned directions

The following are **not** part of this project:

- 3DGS.cpp as a renderer chassis
- Vulkan / MoltenVK prototyping
- Android-first or Vulkan-primary runtime plans
- Porting Vulkan to Metal as an interim step

## Next decision (open)

When runtime work resumes, the choice must be **iOS-native**. A native
iOS/Metal Mobile-GS-style renderer is a candidate, but no scaffolding should
be added until that decision is made explicitly.

See also: `runtime/README.md`, `runtime/ios-runtime-tbd/README.md`.
