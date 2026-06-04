# Spatial Asset Viewer (manifest-first)

Loads a full **SpatialAsset package** via `manifest.json`, not a standalone PLY.

## Run

```bash
npm install
npm run dev
```

Open:

```
http://localhost:5173/?package=/exports/example/manifest.json
```

Use absolute path from repo root (Vite serves parent dirs).

## Mobile benchmark

```
http://<host>:5173/?package=/exports/example/manifest.json&benchmark=1
```

Tap **Export viewer benchmark** on device; save as `exports/example/mobile_benchmarks/ios_viewer_results.json`.

## Package load order

1. `manifest.json`
2. `objects.json`
3. `benchmarks.json`
4. `scene.ply`
5. `object_groups/*.indices`

## Mobile-in-the-loop metrics

When opened with `run_id` and `api` query params (from `GET /runs/{run_id}/result`):

- Collects manifest/package fetch sizes and timing
- Measures load → first render
- Samples frame times for 5s → `average_fps`, `p95_frame_time_ms`
- POSTs JSON to `{api}/runs/{run_id}/mobile-metrics`

Example:

```
http://<host>:5173/?package=http://<host>:8787/exports/demo/manifest.json&run_id=demo-20260101T120000&api=http://<host>:8787&benchmark=1
```
