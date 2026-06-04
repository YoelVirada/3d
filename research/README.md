# Research integrations

## v1 (wired in pipeline)

| Project | Role | Env |
|---------|------|-----|
| [SegAnyGAussians (SAGA)](https://github.com/Jumpat/SegAnyGAussians) | Primary 3D object lifting | `saga-lift` |
| [Gaussian Grouping](https://github.com/lkeab/gaussian-grouping) | Fallback lifting | `gaussian-grouping` |

## v2 (not yet integrated)

| Project | Notes |
|---------|-------|
| [LangSplat](https://github.com/langsplat-community/langsplat) | Language-feature fields |
| [Feature 3DGS](https://github.com/ShijieZhou-UCLA/feature-3dgs) | Feature fields for open-vocab |

Vote-based projection in `object_lifting/projection.py` is **emergency only** when SAGA and GG both fail.
