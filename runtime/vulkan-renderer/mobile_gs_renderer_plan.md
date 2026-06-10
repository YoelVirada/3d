# Plan: Mobile-GS-style order-independent renderer on 3DGS.cpp

## Why

Classic 3DGS renderers (including 3DGS.cpp) depth-sort all splats every frame
and alpha-blend back-to-front. Sorting dominates frame time on mobile GPUs and
forces a global sync. Mobile-GS (and SortFreeGS-style approaches) replace
sorted alpha blending with a **depth-aware order-independent** weighting
(learned φ term), eliminating the per-frame global sort.

## Phases

### Phase 0 — baseline
- Build 3DGS.cpp unmodified (desktop Vulkan; macOS via MoltenVK).
- Render a converted test scene; record frame time breakdown
  (sort vs projection vs blend) as the baseline.

### Phase 1 — asset path
- Feed buffers from our Mobile-GS decoder (`runtime/mobile-gs-decoder`)
  instead of PLY loading.
- Keep the stock sorted pipeline at first to validate the asset path
  end-to-end (decode → GPU buffers → image).

### Phase 2 — swap the sort/blend path
- Identify the sort + blend stages in 3DGS.cpp
  (radix sort dispatch + per-tile blending in the compute path).
- Implement the Mobile-GS weighting: per-fragment contribution
  `w = α · φ(depth)` accumulated order-independently
  (weighted sum + normalization pass), matching the CUDA reference kernels.
- Remove the global sort dispatch; keep tile binning for locality only.

### Phase 3 — parity & perf
- Image-diff against the Mobile-GS CUDA reference renderer on the same
  scenes/cameras; document PSNR.
- Profile on: desktop Vulkan, MoltenVK (macOS), Android Vulkan.
- Record VRAM and frame-time budgets for phone-class targets.

### Phase 4 — packaging direction
- Define the native runtime API: `load(comp.xz) → scene handle → render(camera)`.
- iOS production path: Metal port of the proven pipeline (MoltenVK is the
  research bridge, not the shipping plan).

## Non-goals

- No web viewer of any kind.
- No PLY runtime previews; the runtime consumes the compressed asset only.
- No server-side rendering — all rendering happens on-device.
