import Foundation
import Observation
import OSLog
import CoreGraphics
import Vision

actor CaptureScheduler {
    weak var appState: AppState?
    private var captureTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.personalhistorian.app", category: "CaptureScheduler")
    
    private let screenCapture = ScreenCapture()
    private let ocrEngine = OCREngine()
    private let imageProcessor = ImageProcessor()
    
    func setAppState(_ state: AppState) {
        self.appState = state
    }

    init() {}

    func start() {
        guard captureTask == nil else { return }
        logger.info("Starting capture scheduler")
        captureTask = Task {
            while !Task.isCancelled {
                do {
                    try await performCapture()
                    let interval = await appState?.configuration.captureIntervalSeconds ?? 1
                    try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
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
    
    func captureNow() async {
        logger.info("Manual capture requested")
        do {
            try await performCapture()
            logger.info("Manual capture finished successfully")
        } catch {
            logger.error("Manual capture failed: \(error)")
        }
    }

    private func performCapture() async throws {
        guard let appState = appState else {
            logger.error("Capture skipped: appState is nil!")
            return
        }
        
        logger.info("Performing capture...")
        let startTime = CFAbsoluteTimeGetCurrent()
        let snapshotInfo = await MainActor.run { appState.appTracker.snapshot() }
        
        guard let foreground = snapshotInfo.foreground else {
            logger.debug("Skipping capture: No valid foreground app or app is excluded")
            return
        }
        logger.info("Foreground app: \(foreground.name)")
        
        // 1. Capture Screen
        let cgImage: CGImage
        do {
            cgImage = try await screenCapture.captureMainDisplay()
        } catch {
            logger.error("Capture failed with error: \(error)")
            await MainActor.run {
                appState.permissionStatus = .denied
                appState.stopRecording()
            }
            throw error
        }
        
        // 2. Process concurrently (OCR + Resize/Compress)
        let ocrLevelStr = await appState.configuration.ocrRecognitionLevel
        let ocrLevel: VNRequestTextRecognitionLevel = (ocrLevelStr == "fast") ? .fast : .accurate
        let maxHeight = await appState.configuration.maxResolutionHeight
        let quality = await appState.configuration.imageQuality
        
        async let ocrTask = ocrEngine.recognizeText(in: cgImage, level: ocrLevel)
        async let processTask = Task.detached {
            self.imageProcessor.processForStorage(cgImage, maxHeight: maxHeight, quality: quality)
        }.value
        
        let (ocrText, jpegData) = try await (ocrTask, processTask)
        
        guard let jpegData = jpegData else {
            logger.error("Image processing failed to produce JPEG data")
            return
        }
        
        // 3. Save to disk
        let fileName: String
        do {
            fileName = try appState.screenshotStorage.save(jpegData: jpegData)
        } catch {
            logger.error("Failed to write image to disk: \(error)")
            return
        }
        
        let timestamp = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: timestamp)
        
        // 4. Save to Database
        try await appState.databaseManager.insertSnapshot(
            timestamp: dateString,
            filePath: fileName,
            foregroundApp: foreground.name,
            appBundleId: foreground.bundleIdentifier,
            windowTitle: nil, // Window title extraction not implemented yet
            ocrText: ocrText
        )
        
        await MainActor.run {
            appState.lastCaptureTime = timestamp
            appState.captureCount += 1
        }
        
        let totalMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        logger.debug("Capture completed in \(totalMs)ms for \(foreground.name)")
    }
}
