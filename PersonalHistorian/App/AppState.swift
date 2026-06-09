import Foundation
import Observation

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

@Observable @MainActor
final class AppState {
    let configuration: Configuration
    let databaseManager: DatabaseManager
    let screenshotStorage: ScreenshotStorage
    let searchService: SearchService
    let captureScheduler: CaptureScheduler
    let appTracker: AppTracker

    var permissionStatus: PermissionStatus = .notDetermined

    var isRecording: Bool {
        configuration.isRecording
    }

    init() {
        self.configuration = Configuration()
        
        let customDir = UserDefaults(suiteName: "com.personalhistorian.prefs")?.string(forKey: "testAppSupportDir")
        self.databaseManager = DatabaseManager(customAppSupportPath: customDir)
        self.screenshotStorage = ScreenshotStorage()
        self.searchService = SearchService()
        self.appTracker = AppTracker()
        
        let scheduler = CaptureScheduler()
        self.captureScheduler = scheduler
        scheduler.appState = self
        
        if configuration.isRecording {
            startRecording()
        }
    }

    func startRecording() {
        configuration.isRecording = true
        appTracker.startTracking()
        captureScheduler.start()
    }

    func stopRecording() {
        configuration.isRecording = false
        appTracker.stopTracking()
        captureScheduler.stop()
    }

    func checkPermissions() -> PermissionStatus {
        return permissionStatus
    }
}
