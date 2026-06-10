# Mobile-GS CUDA decode reference

Notes on how Mobile-GS decodes and renders from `comp.xz` in its CUDA
reference implementation. This folder documents and inspects behavior — it
is **not** a client runtime and does not implement iOS rendering.

## Reference

The CUDA code in `third_party/Mobile-GS` is the ground truth:

- `render.py --decode` — renders from `comp.xz` instead of the PLY file;
  results are identical. This is the only valid end-to-end validation until
  an iPhone-native runtime exists.
- CUDA kernels implement Mobile-GS's depth-aware order-independent rendering.

See `notes_from_cuda_reference.md` for working notes on bitstream layout and
decode steps.

## Scope

- Document `comp.xz` container layout (entropy coding, codebooks, streams).
- Record what the CUDA reference does so a future iOS-native renderer can be
  designed from facts, not guesses.

## Out of scope

- Implementing a client renderer (Metal, Vulkan, web, or borrowed engines).
- Standalone C/C++ decode prototypes — paused until runtime direction is chosen.
