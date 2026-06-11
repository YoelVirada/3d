import Foundation

/// Per-iteration stats returned from a training engine.
struct TrainingStatistics: Equatable {
    var iteration: Int
    var splatCount: Int
    var millisecondsPerStep: Float
    // TODO: Loss breakdown, densification events, memory high-water mark.
}
