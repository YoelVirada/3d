# Notes from the Mobile-GS CUDA reference

Working notes while reading `third_party/Mobile-GS`. Update as we inspect
the CUDA decode/render path.

## Entry points to read first

- `render.py` — the `--decode` flag switches the loader from PLY to `comp.xz`.
  Trace what it constructs: this defines the decode behavior to document.
- Compression utilities — Mobile-GS uses neural vector quantization with
  sub-vector decomposition (K clusters of length L, per-cluster codebooks)
  plus GPCC (`tmc3`) for positions. Locate where codebooks and indices are
  serialized into the archive.
- CUDA kernels — depth-aware order-independent blending. The weighting
  function φ (MLP-initialized to 1) replaces sorted alpha blending.

## Questions to answer

- [ ] Exact member list and order inside `comp.xz` (tar? raw lzma streams?)
- [ ] Position stream: GPCC-coded? What `tmc3` profile/settings?
- [ ] Attribute streams: codebook shapes, index bit width, entropy coder
- [ ] What must be dequantized on CPU vs what can stay quantized on GPU
- [ ] Memory layout the CUDA renderer consumes after decode (SoA vs AoS)

## Validation (backend only)

Until an iPhone-native runtime exists, validate on the GPU host:

1. CUDA reference, PLY path
2. CUDA reference, `--decode` path (`comp.xz`)

PSNR between (1) and (2) should match; this is the ground truth for any
future runtime decision.
