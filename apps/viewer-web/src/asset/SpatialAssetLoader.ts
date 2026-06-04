/**
 * Manifest-first Spatial Asset package loader.
 * Primary entry: loadPackage(manifestUrl) — NOT raw scene.ply.
 */

export interface Manifest {
  asset_version: string;
  scene_id: string;
  raw_splat_path: string;
  objects_path: string;
  benchmarks_path: string;
  object_groups_dir: string;
  warnings: string[];
  streaming_hints?: { selection_authority?: string; preview_asset?: string };
}

export interface ObjectEntry {
  id: string;
  label: string;
  splat_count?: number;
  bbox_3d?: { min: number[]; max: number[]; center?: number[] };
  mesh_path?: string | null;
  indices_path?: string | null;
}

export interface ObjectsFile {
  objects: ObjectEntry[];
  lifting_method?: string;
  degraded?: boolean;
}

export interface BenchmarksFile {
  [key: string]: unknown;
}

export interface PackageLoadStats {
  manifestBytes: number;
  manifestFetchMs: number;
  objectsBytes: number;
  benchmarksBytes: number;
  totalDownloadedBytes: number;
}

export class SpatialAssetPackage {
  constructor(
    public baseUrl: string,
    public manifest: Manifest,
    public objects: ObjectsFile,
    public benchmarks: BenchmarksFile,
    public loadStats: PackageLoadStats,
    public indexCache: Map<string, Uint32Array> = new Map()
  ) {}

  getSplatUrl(): string {
    return resolveUrl(this.baseUrl, this.manifest.raw_splat_path);
  }

  selectionAuthority(): "ply" {
    return "ply";
  }

  async getObjectIndices(objectId: string): Promise<Uint32Array | null> {
    if (this.indexCache.has(objectId)) {
      return this.indexCache.get(objectId)!;
    }
    const obj = this.objects.objects.find((o) => o.id === objectId);
    if (!obj) return null;
    const rel =
      obj.indices_path ||
      `${this.manifest.object_groups_dir}${objectId}.indices`;
    const url = resolveUrl(this.baseUrl, rel);
    const res = await fetch(url);
    if (!res.ok) return null;
    const buf = await res.arrayBuffer();
    const arr = new Uint32Array(buf);
    this.indexCache.set(objectId, arr);
    return arr;
  }
}

async function fetchWithStats(url: string): Promise<{ data: Response; bytes: number; ms: number }> {
  const t0 = performance.now();
  const res = await fetch(url);
  const buf = await res.clone().arrayBuffer();
  return { data: res, bytes: buf.byteLength, ms: performance.now() - t0 };
}

export class SpatialAssetLoader {
  static async loadPackage(manifestUrl: string): Promise<SpatialAssetPackage> {
    const t0 = performance.now();
    const manifestRes = await fetch(manifestUrl);
    if (!manifestRes.ok) {
      throw new Error(`Failed to load manifest: ${manifestUrl}`);
    }
    const manifestBuf = await manifestRes.clone().arrayBuffer();
    const manifest: Manifest = JSON.parse(new TextDecoder().decode(manifestBuf));
    const manifestFetchMs = performance.now() - t0;
    const baseUrl = manifestUrl.replace(/\/[^/]*$/, "/");

    const [objectsRes, benchRes] = await Promise.all([
      fetchWithStats(resolveUrl(baseUrl, manifest.objects_path)),
      fetchWithStats(resolveUrl(baseUrl, manifest.benchmarks_path)),
    ]);
    if (!objectsRes.data.ok) throw new Error("Failed to load objects.json");
    const objects: ObjectsFile = await objectsRes.data.json();
    const benchmarks: BenchmarksFile = benchRes.data.ok
      ? await benchRes.data.json()
      : {};

    const loadStats: PackageLoadStats = {
      manifestBytes: manifestBuf.byteLength,
      manifestFetchMs,
      objectsBytes: objectsRes.bytes,
      benchmarksBytes: benchRes.bytes,
      totalDownloadedBytes:
        manifestBuf.byteLength + objectsRes.bytes + benchRes.bytes,
    };

    return new SpatialAssetPackage(baseUrl, manifest, objects, benchmarks, loadStats);
  }
}

export function resolveUrl(base: string, rel: string): string {
  if (rel.startsWith("http")) return rel;
  const b = base.endsWith("/") ? base : base + "/";
  return new URL(rel.replace(/^\//, ""), b).href;
}
