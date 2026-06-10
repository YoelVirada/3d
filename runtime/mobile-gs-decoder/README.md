# Mobile-GS decoder (reference layer)

Goal: understand and reimplement the decode path of the Mobile-GS compressed
asset (`comp.xz`) so a native runtime can load it **without** the training
stack.

## Reference

The CUDA implementation in `third_party/Mobile-GS` is the reference point:

- `render.py --decode` — renders directly from `comp.xz` instead of the PLY,
  with identical results. This is the ground-truth decode behavior.
- The CUDA kernels implement Mobile-GS's depth-aware order-independent
  rendering — the same math the native renderer must reproduce.

See `notes_from_cuda_reference.md` for the working notes on the bitstream
layout and decode steps as extracted from the reference code.

## Deliverables (research phase)

1. Documented `comp.xz` container layout (entropy coding, quantization
   codebooks, attribute streams).
2. A standalone C/C++ decode prototype: `comp.xz` → GPU-uploadable buffers
   (positions, rotations, scales, opacities, SH/color attributes).
3. Validation: decoded buffers match the CUDA reference decode bit-exactly
   (or within documented quantization tolerance).

No web viewer, no PLY intermediate — decode targets GPU buffers directly.
