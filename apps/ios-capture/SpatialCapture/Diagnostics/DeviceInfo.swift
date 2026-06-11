import UIKit

enum DeviceInfo {
    static var modelIdentifier: String {
        UIDevice.current.model
    }

    static var osVersion: String {
        UIDevice.current.systemVersion
    }

    static var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
