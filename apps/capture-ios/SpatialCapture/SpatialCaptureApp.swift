import SwiftUI

@main
struct SpatialCaptureApp: App {
    @StateObject private var settings = CaptureSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
    }
}
