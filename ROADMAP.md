# Roadmap

## v0.1 (current)

- [x] Capture server + iOS skeleton
- [x] Full pipeline orchestrator
- [x] Pinned main env (torch 2.6.0+cu124, gsplat 1.4.0, nerfstudio v1.1.5)
- [x] SAGA + Gaussian Grouping object lifting (isolated heavy envs)
- [x] Manifest-first WebGPU viewer (`scene.ply`)
- [x] Per-object Open3D meshes (top-N)
- [x] Strict setup/verify scripts (`verify_deps.sh`, `doctor.sh`)

## v0.2

- [ ] Full SAGA feature training on 2080 Ti production profile
- [ ] SAM2 video propagation (not just keyframes)
- [ ] LangSplat / Feature 3D GS research integration

## v0.3 — spatial codec (future)

The official compression/codec layer is intentionally not implemented yet. SPZ-style splat compression was removed from the official pipeline. The target direction is a **learned / neural / codebook-based spatial codec**, designed separately from conventional splat export tools.

- [ ] Codec requirements + evaluation harness
- [ ] Progressive object-level chunks
- [ ] LOD per object
- [ ] Unified streaming protocol

## Known gaps (honest)

- SuGaR scene mesh requires trained SuGaR model in `sugar-mesh` env
- SAGA full train may need overnight on 2080 Ti
- iOS WebGPU requires Safari iOS 26+
