import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class CaptureScheduler {
    weak var appState: AppState?
    private var captureTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.personalhistorian.app", category: "CaptureScheduler")

    init() {}

    func start() {
        guard captureTask == nil else { return }
        logger.info("Starting capture scheduler")
        captureTask = Task {
            while !Task.isCancelled {
                do {
                    try await performCapture()
                    let interval = UInt64(appState?.configuration.captureIntervalSeconds ?? 1) * 1_000_000_000
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    if !Task.isCancelled {
                        logger.error("Capture task error: \(error)")
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
        }
    }

    func stop() {
        logger.info("Stopping capture scheduler")
        captureTask?.cancel()
        captureTask = nil
    }

    private func performCapture() async throws {
        guard let appState = appState else { return }
        
        let snapshotInfo = appState.appTracker.snapshot()
        
        // Skip capture if no valid foreground app or if it's excluded (which results in nil foreground)
        guard let foreground = snapshotInfo.foreground else {
            logger.debug("Skipping capture: No valid foreground app or app is excluded")
            return
        }
        
        let activeAppName = foreground.name
        let activeAppId = foreground.bundleIdentifier
        let timestamp = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: timestamp)
        
        try appState.databaseManager.insertSnapshot(
            timestamp: dateString,
            filePath: "dummy_path.jpg",
            foregroundApp: activeAppName,
            appBundleId: activeAppId,
            windowTitle: nil,
            ocrText: nil
        )
    }
}
