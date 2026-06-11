import Foundation

/// Capture and training performance counters.
struct PerformanceStatistics: Equatable {
    var captureFPS: Float?
    var trainingIterationsPerSecond: Float?
    // TODO: Feed from ARCaptureView frame loop and GaussianTrainerProtocol step timing.
}
