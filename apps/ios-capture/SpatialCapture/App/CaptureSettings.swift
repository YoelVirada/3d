import Foundation

/// App-level capture and research settings.
final class CaptureSettings: ObservableObject {
    @Published var sessionLabel: String {
        didSet { UserDefaults.standard.set(sessionLabel, forKey: "sessionLabel") }
    }

    /// Legacy server upload path (Mobile-GS GPU pipeline). Off by default.
    @Published var legacyServerUploadEnabled: Bool {
        didSet { UserDefaults.standard.set(legacyServerUploadEnabled, forKey: "legacyServerUploadEnabled") }
    }

    @Published var legacyServerBaseURL: String {
        didSet { UserDefaults.standard.set(legacyServerBaseURL, forKey: "legacyServerBaseURL") }
    }

  @Published var legacySceneId: String {
        didSet { UserDefaults.standard.set(legacySceneId, forKey: "legacySceneId") }
    }

    init() {
        sessionLabel = UserDefaults.standard.string(forKey: "sessionLabel") ?? "capture"
        legacyServerUploadEnabled = UserDefaults.standard.bool(forKey: "legacyServerUploadEnabled")
        legacyServerBaseURL = UserDefaults.standard.string(forKey: "legacyServerBaseURL")
            ?? "http://10.100.102.12:8787"
        legacySceneId = UserDefaults.standard.string(forKey: "legacySceneId") ?? "example"
    }
}
