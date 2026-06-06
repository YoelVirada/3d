import { SpatialAssetLoader, SpatialAssetPackage } from "./asset/SpatialAssetLoader";
import { postMobileMetrics, sampleFrameTimes } from "./benchmark/mobileMetrics";
import { SplatRenderer } from "./renderer/SplatRenderer";

const params = new URLSearchParams(location.search);
const manifestParam = params.get("package");
const runId = params.get("run_id");
const apiBase = params.get("api");
const benchmarkMode = params.get("benchmark") === "1" || !!runId;

const sidebar = document.getElementById("sidebar")!;
const container = document.getElementById("canvas-container")!;

let pkg: SpatialAssetPackage | null = null;
let renderer: SplatRenderer | null = null;
let fpsFrames = 0;
let fpsLast = performance.now();
let fpsValue = 0;
let selectedId: string | null = null;

interface RenderStats {
  loadMs: number;
  firstFrameMs: number;
  splatBytes: number | null;
  splatFetchMs: number | null;
}

function renderSidebar(p: SpatialAssetPackage, stats: RenderStats) {
  const metricsNote =
    runId && apiBase
      ? `<div class="stat">Metrics: auto-post to server</div>`
      : `<div class="stat">Add ?run_id=&api= to auto-report</div>`;
  sidebar.innerHTML = `
    <h1>Spatial Asset</h1>
    <div class="stat">Scene: ${p.manifest.scene_id}</div>
    <div class="stat">Asset v${p.manifest.asset_version}</div>
    ${runId ? `<div class="stat">Run: ${runId}</div>` : ""}
    <h2>Render</h2>
    <div class="stat">Splat: ${p.getSplatUrl().split("/").pop() ?? p.manifest.raw_splat_path}</div>
    <div class="stat">Raw PLY: ${p.manifest.raw_splat_path}</div>
    <div class="stat">Manifest fetch: ${p.loadStats.manifestFetchMs.toFixed(0)} ms (${p.loadStats.manifestBytes} B)</div>
    <div class="stat">Package fetch: ${p.loadStats.totalDownloadedBytes} B</div>
    <div class="stat">Load: ${stats.loadMs.toFixed(0)} ms</div>
    <div class="stat">First frame: ${stats.firstFrameMs.toFixed(0)} ms</div>
    <div class="stat">FPS: <span id="fps">—</span></div>
    <div class="stat">WebGPU: <span id="wgpu">…</span></div>
    ${metricsNote}
    <h2>Objects (${p.objects.objects.length})</h2>
    <div id="obj-list"></div>
    <h2>Benchmarks</h2>
    <pre class="stat" style="white-space:pre-wrap;font-size:10px;max-height:120px;overflow:auto">${JSON.stringify(p.benchmarks, null, 0).slice(0, 800)}</pre>
    <button id="export-bench">Export viewer benchmark (JSON)</button>
  `;

  const list = document.getElementById("obj-list")!;
  for (const o of p.objects.objects) {
    const el = document.createElement("div");
    el.className = "obj-item" + (o.id === selectedId ? " selected" : "");
    el.textContent = `${o.label} (${o.splat_count ?? "?"} splats)`;
    el.onclick = () => selectObject(o.id);
    list.appendChild(el);
  }

  document.getElementById("export-bench")!.onclick = () => exportBenchmark(stats);
}

async function selectObject(id: string) {
  selectedId = id;
  if (!pkg) return;
  const indices = await pkg.getObjectIndices(id);
  console.log(`Selected ${id}: ${indices?.length ?? 0} indices`);
  if (pkg) renderSidebar(pkg, lastStats);
}

let lastStats: RenderStats = {
  loadMs: 0,
  firstFrameMs: 0,
  splatBytes: null,
  splatFetchMs: null,
};

async function exportBenchmark(stats: RenderStats) {
  const adapter = await navigator.gpu?.requestAdapter();
  const report = {
    exported_at: new Date().toISOString(),
    manifest: manifestParam,
    run_id: runId,
    load_time_ms: stats.loadMs,
    first_frame_time_ms: stats.firstFrameMs,
    fps: fpsValue,
    webgpu_available: !!navigator.gpu,
    gpu_adapter: adapter?.info?.description ?? null,
    benchmark_mode: benchmarkMode,
    user_agent: navigator.userAgent,
  };
  const blob = new Blob([JSON.stringify(report, null, 2)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "viewer_benchmark.json";
  a.click();
}

async function reportMobileMetrics(stats: RenderStats, frameSample: Awaited<ReturnType<typeof sampleFrameTimes>>) {
  if (!runId || !apiBase || !pkg) return;
  const splatUrl = pkg.getSplatUrl();
  let downloaded = pkg.loadStats.totalDownloadedBytes;
  if (stats.splatBytes) downloaded += stats.splatBytes;

  await postMobileMetrics(apiBase, runId, {
    viewer_url: location.href,
    manifest_bytes: pkg.loadStats.manifestBytes,
    downloaded_asset_bytes: downloaded,
    viewer_load_time_ms: stats.loadMs,
    time_to_first_render_ms: stats.firstFrameMs,
    average_fps: frameSample.averageFps,
    p95_frame_time_ms: frameSample.p95FrameTimeMs,
    render_error: null,
    extra: {
      source: "viewer-web",
      manifest_fetch_ms: pkg.loadStats.manifestFetchMs,
      splat_fetch_ms: stats.splatFetchMs,
      splat_bytes: stats.splatBytes,
      user_agent: navigator.userAgent,
      webgpu: !!navigator.gpu,
    },
  });
  const note = document.querySelector("#metrics-status");
  if (note) note.textContent = "Metrics sent to server";
}

function tickFps() {
  fpsFrames++;
  const now = performance.now();
  if (now - fpsLast >= 1000) {
    fpsValue = Math.round((fpsFrames * 1000) / (now - fpsLast));
    fpsFrames = 0;
    fpsLast = now;
    const el = document.getElementById("fps");
    if (el) el.textContent = String(fpsValue);
  }
  requestAnimationFrame(tickFps);
}

async function main() {
  if (!manifestParam) {
    sidebar.innerHTML = `<div id="error">Missing ?package= URL to manifest.json<br><br>Example:<br><code>?package=http://HOST:8787/exports/example/manifest.json&run_id=...&api=http://HOST:8787</code></div>`;
    return;
  }

  const wgpuEl = () => document.getElementById("wgpu");
  if (navigator.gpu) {
    const adapter = await navigator.gpu.requestAdapter();
    setTimeout(() => {
      if (wgpuEl()) wgpuEl()!.textContent = adapter ? "yes" : "no adapter";
    }, 100);
  } else {
    setTimeout(() => {
      if (wgpuEl()) wgpuEl()!.textContent = "no";
    }, 100);
  }

  try {
    const loadStart = performance.now();
    pkg = await SpatialAssetLoader.loadPackage(manifestParam);
    renderer = new SplatRenderer(container);
    const splatUrl = pkg.getSplatUrl();
    const splatProbe = await fetch(splatUrl, { method: "HEAD" }).catch(() => null);
    let splatBytes: number | null = null;
    if (splatProbe?.ok) {
      const cl = splatProbe.headers.get("content-length");
      splatBytes = cl ? parseInt(cl, 10) : null;
    }
    lastStats = await renderer.load(splatUrl);
    lastStats.splatBytes = splatBytes;
    renderSidebar(pkg, lastStats);
    tickFps();

    if (benchmarkMode && runId && apiBase) {
      const frameSample = await sampleFrameTimes(5000);
      try {
        await reportMobileMetrics(lastStats, frameSample);
      } catch (e) {
        console.warn("mobile-metrics post failed", e);
      }
    }
  } catch (e) {
    sidebar.innerHTML = `<div id="error">${e}</div>`;
    console.error(e);
    if (runId && apiBase) {
      try {
        await postMobileMetrics(apiBase, runId, {
          viewer_url: location.href,
          render_error: String(e),
          extra: { source: "viewer-web" },
        });
      } catch {
        /* ignore */
      }
    }
  }
}

main();
