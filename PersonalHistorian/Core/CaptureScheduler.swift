import Foundation
import Observation
import OSLog
import CoreGraphics
import Vision

actor CaptureScheduler {
    weak var appState: AppState?
    private var captureTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.personalhistorian.app", category: "CaptureScheduler")
    
    private var lastHash: String?
    private var lastFileName: String?
    private var lastOCRText: String?
    
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
        
        let maxHeight = await appState.configuration.maxResolutionHeight
        let quality = await appState.configuration.imageQuality
        
        // Resize first for faster hashing
        guard let resizedImage = imageProcessor.resize(cgImage, maxHeight: maxHeight) else {
            logger.error("Failed to resize image")
            return
        }
        
        let currentHash = imageProcessor.hash(image: resizedImage)
        
        let timestamp = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: timestamp)
        
        // 2. Deduplication check
        if currentHash == lastHash, let fileName = lastFileName {
            logger.info("Image identical to last capture. Deduplicating.")
            
            try await appState.databaseManager.insertSnapshot(
                timestamp: dateString,
                filePath: fileName,
                foregroundApp: foreground.name,
                appBundleId: foreground.bundleIdentifier,
                windowTitle: foreground.windowTitle,
                ocrText: lastOCRText
            )
            
            await MainActor.run {
                appState.lastCaptureTime = timestamp
                appState.captureCount += 1
            }
            
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            logger.debug("Deduplicated capture completed in \(totalMs)ms for \(foreground.name)")
            return
        }
        
        // 3. Process concurrently (OCR + Compress)
        let ocrLevelStr = await appState.configuration.ocrRecognitionLevel
        let ocrLevel: VNRequestTextRecognitionLevel = (ocrLevelStr == "fast") ? .fast : .accurate
        
        async let ocrTask = ocrEngine.recognizeText(in: resizedImage, level: ocrLevel)
        async let heicDataTask = Task.detached {
            self.imageProcessor.compressToHEIC(resizedImage, quality: quality)
        }.value
        
        let (ocrText, heicData) = try await (ocrTask, heicDataTask)
        
        guard let heicData = heicData else {
            logger.error("Image processing failed to produce HEIC data")
            return
        }
        
        // 4. Save to disk
        let fileName: String
        do {
            fileName = try appState.screenshotStorage.save(imageData: heicData, hash: currentHash, fileExtension: "heic")
        } catch {
            logger.error("Failed to write image to disk: \(error)")
            return
        }
        
        // Update state
        self.lastHash = currentHash
        self.lastFileName = fileName
        self.lastOCRText = ocrText
        
        // 5. Save to Database
        try await appState.databaseManager.insertSnapshot(
            timestamp: dateString,
            filePath: fileName,
            foregroundApp: foreground.name,
            appBundleId: foreground.bundleIdentifier,
            windowTitle: foreground.windowTitle,
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
