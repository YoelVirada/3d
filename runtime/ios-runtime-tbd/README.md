# iOS runtime — TBD

No iOS runtime exists in this repository yet.

## Status

**Intentionally undecided.** The product is iPhone-first, but we have not
chosen or started implementing a client-side renderer.

## What exists today

1. `apps/ios-capture/` — records and uploads capture video.
2. `server/capture-upload/` + `training/mobile-gs/` — produces `comp.xz`.
3. Backend validation via Mobile-GS `render.py --decode` on the GPU host.

The pipeline ends at `comp.xz`. Nothing in this folder renders on the phone.

## What does not belong here (yet)

- Metal scaffolding or placeholder render code
- Borrowed renderers (3DGS.cpp, Vulkan, MoltenVK, web viewers)
- Android or cross-platform runtime experiments

When we pick an iPhone-native approach, this folder is where that work will
live. Until then, it stays empty except for this document.
