import Foundation

enum TrainingState: String, Equatable {
    case idle
    case preparingDataset
    case training
    case paused
    case completed
    case failed
}
