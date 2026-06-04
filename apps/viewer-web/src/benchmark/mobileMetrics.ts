/** Collect viewer load/render metrics and POST to capture server. */

export interface LoadFetchStats {
  manifestBytes: number;
  manifestFetchMs: number;
  objectsBytes: number;
  benchmarksBytes: number;
  splatBytes: number | null;
  splatFetchMs: number | null;
  totalDownloadedBytes: number;
}

export interface FrameSample {
  frameTimesMs: number[];
  averageFps: number;
  p95FrameTimeMs: number;
}

export function sampleFrameTimes(durationMs: number): Promise<FrameSample> {
  return new Promise((resolve) => {
    const times: number[] = [];
    let last = performance.now();
    let raf = 0;
    const endAt = last + durationMs;

    const tick = (now: number) => {
      times.push(now - last);
      last = now;
      if (now < endAt) {
        raf = requestAnimationFrame(tick);
      } else {
        cancelAnimationFrame(raf);
        const avgFt =
          times.length > 0 ? times.reduce((a, b) => a + b, 0) / times.length : 0;
        const sorted = [...times].sort((a, b) => a - b);
        const p95 = sorted[Math.floor(sorted.length * 0.95)] ?? avgFt;
        resolve({
          frameTimesMs: times,
          averageFps: avgFt > 0 ? 1000 / avgFt : 0,
          p95FrameTimeMs: p95,
        });
      }
    };
    raf = requestAnimationFrame(tick);
  });
}

export async function postMobileMetrics(
  apiBase: string,
  runId: string,
  payload: Record<string, unknown>
): Promise<void> {
  const base = apiBase.replace(/\/$/, "");
  const url = `${base}/runs/${encodeURIComponent(runId)}/mobile-metrics`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ run_id: runId, timestamp: new Date().toISOString(), ...payload }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`mobile-metrics failed: ${res.status} ${text}`);
  }
}
