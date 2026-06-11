import Foundation

/// Swift-side contract for msplat on-device training (implementation pending).
protocol GaussianTrainerProtocol {
    // TODO: Wire to msplat C API / MsplatCore XCFramework when iOS target is available.
    func step() -> TrainingStatistics
    func exportPly(to path: String) throws
}
