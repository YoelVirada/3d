import Foundation

final class CaptureSettings: ObservableObject {
    @Published var serverBaseURL: String {
        didSet { UserDefaults.standard.set(serverBaseURL, forKey: "serverBaseURL") }
    }
    @Published var sceneId: String {
        didSet { UserDefaults.standard.set(sceneId, forKey: "sceneId") }
    }

    init() {
        serverBaseURL = UserDefaults.standard.string(forKey: "serverBaseURL")
            ?? "http://192.168.1.100:8787"
        sceneId = UserDefaults.standard.string(forKey: "sceneId") ?? "example"
    }
}
