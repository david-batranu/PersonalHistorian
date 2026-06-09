import Foundation
import Observation

@Observable
final class Configuration {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: "com.personalhistorian.prefs") ?? .standard) {
        self.defaults = defaults
        
        // Register defaults
        defaults.register(defaults: [
            "captureIntervalSeconds": 60,
            "ocrRecognitionLevel": "accurate",
            "imageQuality": 0.7,
            "maxResolutionHeight": 1080,
            "retentionDays": 30,
            "excludedBundleIDs": [String](),
            "isRecording": true,
            "launchAtLogin": false
        ])
    }

    var captureIntervalSeconds: Int {
        get {
            access(keyPath: \.captureIntervalSeconds)
            return defaults.integer(forKey: "captureIntervalSeconds")
        }
        set {
            withMutation(keyPath: \.captureIntervalSeconds) {
                defaults.set(newValue, forKey: "captureIntervalSeconds")
            }
        }
    }

    var ocrRecognitionLevel: String {
        get {
            access(keyPath: \.ocrRecognitionLevel)
            return defaults.string(forKey: "ocrRecognitionLevel") ?? "accurate"
        }
        set {
            withMutation(keyPath: \.ocrRecognitionLevel) {
                defaults.set(newValue, forKey: "ocrRecognitionLevel")
            }
        }
    }

    var imageQuality: Double {
        get {
            access(keyPath: \.imageQuality)
            return defaults.double(forKey: "imageQuality")
        }
        set {
            withMutation(keyPath: \.imageQuality) {
                defaults.set(newValue, forKey: "imageQuality")
            }
        }
    }

    var maxResolutionHeight: Int {
        get {
            access(keyPath: \.maxResolutionHeight)
            return defaults.integer(forKey: "maxResolutionHeight")
        }
        set {
            withMutation(keyPath: \.maxResolutionHeight) {
                defaults.set(newValue, forKey: "maxResolutionHeight")
            }
        }
    }

    var retentionDays: Int {
        get {
            access(keyPath: \.retentionDays)
            return defaults.integer(forKey: "retentionDays")
        }
        set {
            withMutation(keyPath: \.retentionDays) {
                defaults.set(newValue, forKey: "retentionDays")
            }
        }
    }

    var excludedBundleIDs: [String] {
        get {
            access(keyPath: \.excludedBundleIDs)
            return defaults.stringArray(forKey: "excludedBundleIDs") ?? []
        }
        set {
            withMutation(keyPath: \.excludedBundleIDs) {
                defaults.set(newValue, forKey: "excludedBundleIDs")
            }
        }
    }

    var isRecording: Bool {
        get {
            access(keyPath: \.isRecording)
            return defaults.bool(forKey: "isRecording")
        }
        set {
            withMutation(keyPath: \.isRecording) {
                defaults.set(newValue, forKey: "isRecording")
            }
        }
    }

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return defaults.bool(forKey: "launchAtLogin")
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                defaults.set(newValue, forKey: "launchAtLogin")
            }
        }
    }
}
