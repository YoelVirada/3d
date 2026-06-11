import Foundation

/// Device thermal and memory pressure placeholders for training guardrails.
struct ThermalMemoryState: Equatable {
    var thermalState: ProcessInfo.ThermalState
    // TODO: Query os_proc_available_memory and track peak allocation during capture/training.
}
