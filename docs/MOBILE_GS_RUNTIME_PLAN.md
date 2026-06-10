# Mobile-GS native runtime plan

End state: a native runtime that takes `comp.xz` from the server, decodes it
on device, uploads buffers to the GPU, and renders locally in real time.

## Workstreams

### A. Decoder (`runtime/mobile-gs-decoder/`)

1. Read the Mobile-GS CUDA reference (`render.py --decode` path) and document
   the `comp.xz` container: position stream (GPCC/tmc3), attribute codebooks
   (neural vector quantization, sub-vector decomposition), entropy coding.
2. Prototype a standalone C/C++ decoder producing GPU-ready buffers.
3. Validate bit-exact (or tolerance-documented) parity against the CUDA
   reference decode.

### B. Renderer (`runtime/vulkan-renderer/`)

1. Build 3DGS.cpp unmodified; capture baseline frame-time breakdown.
2. Wire decoder output into its asset path (bypass PLY loading).
3. Replace the global depth sort + back-to-front alpha blend with the
   Mobile-GS depth-aware order-independent formulation
   (weighted accumulation + normalization; φ(depth) weighting per the
   reference kernels). This is the core research deliverable.
4. Image-parity checks against the CUDA reference renderer (PSNR per scene).

### C. Platform bring-up

| Platform | Path |
|----------|------|
| Linux / Windows desktop | Vulkan, native |
| macOS | MoltenVK (research) |
| Android | Vulkan, native |
| iOS | **Vulkan is not native** — MoltenVK for research; production requires a Metal port |

### D. Packaging

- Runtime API: `load(comp.xz)` → scene handle → `render(camera)` → frame.
- Ship as a native library the capture app (or any client) can embed.
- The server's role ends at producing/serving `comp.xz`; no server rendering,
  no frame streaming.

## Milestones

1. **M1** — comp.xz layout documented; CPU decode prototype matches reference.
2. **M2** — 3DGS.cpp renders a decoded Mobile-GS scene (stock sorted pipeline).
3. **M3** — order-independent path replaces sorting; parity PSNR documented.
4. **M4** — runs on a phone-class device (Android Vulkan or iOS/MoltenVK).
5. **M5** — runtime library API + iOS Metal port decision.
