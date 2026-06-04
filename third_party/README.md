# Third-party tools

Pinned in [`versions.lock.json`](versions.lock.json). Synced by **`bash scripts/setup_third_party.sh --yes`** (clone or fetch + checkout — never leave repos on stale HEAD).

Compatibility notes are in the `compatibility` section of the lock file.

| Tool | Ref (lock) | Integration | Env |
|------|------------|-------------|-----|
| nerfstudio | v1.1.5 | `pip install -e third_party/nerfstudio` | spatial-asset-clean |
| gsplat | **v1.4.0** | `pip install --no-build-isolation -e third_party/gsplat` | spatial-asset-clean |
| sam2 | main | `pip install -e third_party/sam2` + checkpoints | spatial-asset-clean |
| SegAnyGAussians | main | subprocess | saga-lift |
| gaussian-grouping | main | subprocess | gaussian-grouping |
| SuGaR | main (recursive) | subprocess | sugar-mesh |

**Critical:** nerfstudio v1.1.5 requires gsplat==1.4.0. Do not checkout gsplat v1.5.x.

After `setup_third_party.sh`, each repo HEAD is logged in `third_party/setup.log`.

Logs: `third_party/setup.log`, `logs/setup/heavy_envs_status.json`.
