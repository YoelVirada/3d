import Foundation

/// ARKit tracking quality at capture time.
enum CaptureTrackingState: String, Codable, Equatable {
    case normal
    case limited
    case notAvailable
    case unknown
}
