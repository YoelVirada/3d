import Foundation

/// Dataset handle for msplat training from a local capture session.
protocol GaussianDatasetProtocol {
    var sessionDirectory: URL { get }
    var trainImageCount: Int { get }
    // TODO: Map LocalCaptureSession / COLMAP export to msplat_dataset_create.
}
