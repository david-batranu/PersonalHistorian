import Foundation
import Observation
import AppKit
import CoreGraphics

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
    let systemObserver: SystemObserver
    let retentionManager: RetentionManager
    
    var permissionStatus: PermissionStatus = .notDetermined
    
    var lastCaptureTime: Date?
    var captureCount: Int = 0

    var isRecording: Bool {
        configuration.isRecording
    }

    init() {
        self.configuration = Configuration()
        self.permissionStatus = CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        
        let customDir = UserDefaults(suiteName: "com.personalhistorian.prefs")?.string(forKey: "testAppSupportDir")
        self.databaseManager = DatabaseManager(customAppSupportPath: customDir)
        self.screenshotStorage = ScreenshotStorage()
        self.searchService = SearchService(dbManager: self.databaseManager)
        self.appTracker = AppTracker()
        self.retentionManager = RetentionManager(dbManager: self.databaseManager, storage: self.screenshotStorage)
        
        let scheduler = CaptureScheduler()
        self.captureScheduler = scheduler
        
        let observer = SystemObserver()
        self.systemObserver = observer
        
        Task {
            await scheduler.setAppState(self)
        }
        observer.appState = self
        self.appTracker.appState = self
        
        // Check permission before starting
        self.permissionStatus = checkPermissions()
        
        if configuration.isRecording {
            if self.permissionStatus == .granted {
                startRecording()
            } else {
                configuration.isRecording = false
            }
        }
        
        Task {
            await self.retentionManager.cleanOldData()
        }
        
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleTermination()
            }
        }
    }
    
    private func handleTermination() {
        stopRecording()
        // Wait briefly for pending writes if necessary, or let DB pool finish
        systemObserver.stop()
    }

    func startRecording() {
        configuration.isRecording = true
        appTracker.startTracking()
        Task {
            await captureScheduler.start()
        }
    }

    func stopRecording() {
        configuration.isRecording = false
        appTracker.stopTracking()
        Task {
            await captureScheduler.stop()
        }
    }

    func checkPermissions() -> PermissionStatus {
        let isGranted = CGPreflightScreenCaptureAccess()
        permissionStatus = isGranted ? .granted : .notDetermined
        return permissionStatus
    }
}
