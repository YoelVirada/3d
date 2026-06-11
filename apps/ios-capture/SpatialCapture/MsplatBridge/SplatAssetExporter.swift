import Foundation

/// Export trained splats for inspection or sharing.
protocol SplatAssetExporter {
    // TODO: PLY, .splat, checkpoint.msplat once msplat trainer is linked.
    func exportPly(to url: URL) throws
    func exportSplat(to url: URL) throws
}
