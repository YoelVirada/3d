# Vulkan renderer prototype

Native renderer research layer. Starting point is
[3DGS.cpp](https://github.com/shg8/3DGS.cpp) — a cross-platform Vulkan
implementation of 3D Gaussian Splatting — cloned (not vendored) into
`third_party/3DGS.cpp/`.

```bash
git clone --recursive https://github.com/shg8/3DGS.cpp third_party/3DGS.cpp
```

Do not modify the clone in place; renderer work happens in our own code that
links against / forks it deliberately. See `mobile_gs_renderer_plan.md` for
the plan to replace its sort + alpha-blend path with a Mobile-GS-style
depth-aware order-independent pipeline.

## Goal

Load a decoded Mobile-GS asset (from `runtime/mobile-gs-decoder`), upload
buffers to the GPU, and render locally — no server-side rendering, no video
streaming, no web viewer.

## Platform note: iOS

**Vulkan is not native on iOS/macOS.** Options, in order:

1. **MoltenVK** — run the Vulkan prototype on Metal via the MoltenVK
   translation layer. Good for research parity with desktop.
2. **Metal port** — the production path for iOS is a native Metal renderer
   once the order-independent pipeline is proven under MoltenVK.

Desktop Linux/Windows (and Android) run Vulkan directly.
