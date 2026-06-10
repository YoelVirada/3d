# Runtime (intentionally not implemented)

The runtime layer is **not implemented yet**. This repository currently stops
at the backend artifact: a Mobile-GS compressed asset (`comp.xz`).

## Product direction

- **iPhone-first.** The client runtime, when chosen, must be iOS-native.
- The backend produces `comp.xz` via Mobile-GS training/compression.
- The next runtime decision is still open.

## What we are not using

We will **not** use any of the following as the main runtime path:

- PlayCanvas, SOG, SPZ, LMG
- Nerfstudio, Splatfacto, gsplat
- 3DGS.cpp
- Vulkan, MoltenVK, or Android-first rendering

## Candidate future direction

A native iOS/Metal Mobile-GS-style renderer is a possible future direction.
**Do not scaffold it yet.** No placeholder rendering code belongs in this repo
until a deliberate runtime choice is made.

## Until a runtime is chosen

The only valid end-to-end validation is **backend-side**:

```bash
python render.py -s <colmap_dataset> -m <model_path> --decode
```

(run inside `third_party/Mobile-GS` after train/compress)

## Layout

| Path | Purpose |
|------|---------|
| `runtime/ios-runtime-tbd/` | Documented gap — iPhone-native runtime undecided |
| `runtime/mobile-gs-decoder/` | Notes on Mobile-GS CUDA decode behavior (reference only) |
