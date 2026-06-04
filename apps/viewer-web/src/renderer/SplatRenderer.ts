/**
 * Internal splat renderer adapter (GaussianSplats3D).
 * Not the public entry — use SpatialAssetLoader.
 */

import * as GaussianSplats3D from "@mkkellogg/gaussian-splats-3d";

export class SplatRenderer {
  private viewer: GaussianSplats3D.Viewer | null = null;
  private loadStart = 0;
  private firstFrame = 0;

  constructor(private container: HTMLElement) {}

  async load(splatUrl: string): Promise<{ loadMs: number; firstFrameMs: number }> {
    this.loadStart = performance.now();
    if (this.viewer) {
      this.viewer.dispose();
    }
    this.viewer = new GaussianSplats3D.Viewer({
      rootElement: this.container,
      cameraUp: [0, -1, 0],
      initialCameraPosition: [0, 2, 4],
      initialCameraLookAt: [0, 0, 0],
      sharedMemoryForWorkers: false,
      gpuAcceleratedSort: true,
    });

    await this.viewer.addSplatScene(splatUrl, {
      showLoadingUI: true,
      progressiveLoad: true,
    });
    await this.viewer.start();

    const loadMs = performance.now() - this.loadStart;
    this.firstFrame = performance.now();
    const firstFrameMs = this.firstFrame - this.loadStart;
    return { loadMs, firstFrameMs };
  }

  getViewer(): GaussianSplats3D.Viewer | null {
    return this.viewer;
  }

  dispose(): void {
    this.viewer?.dispose();
    this.viewer = null;
  }
}
