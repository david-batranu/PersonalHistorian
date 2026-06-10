import Foundation
import Observation
import OSLog
import CoreGraphics
import Vision

/// Per-cycle timing metrics for the capture pipeline.
struct CaptureMetrics: CustomStringConvertible {
    let captureMs: Int
    let resizeMs: Int
    let ocrMs: Int
    let compressMs: Int
    let saveMs: Int
    let dbMs: Int
    let totalMs: Int
    let deduplicated: Bool

    var description: String {
        if deduplicated {
            return "Deduplicated | total=\(totalMs)ms"
        }
        return "capture=\(captureMs)ms resize=\(resizeMs)ms ocr=\(ocrMs)ms compress=\(compressMs)ms save=\(saveMs)ms db=\(dbMs)ms total=\(totalMs)ms"
    }
}

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
        let pipelineStart = CFAbsoluteTimeGetCurrent()
        let snapshotInfo = await MainActor.run { appState.appTracker.snapshot() }

        guard let foreground = snapshotInfo.foreground else {
            logger.debug("Skipping capture: No valid foreground app or app is excluded")
            return
        }
        logger.info("Foreground app: \(foreground.name)")

        // 1. Capture Screen
        let cgImage: CGImage
        let captureStart = CFAbsoluteTimeGetCurrent()
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
        let captureMs = Int((CFAbsoluteTimeGetCurrent() - captureStart) * 1000)

        let maxHeight = await appState.configuration.maxResolutionHeight
        let quality = await appState.configuration.imageQuality

        // Resize first for faster hashing
        let resizeStart = CFAbsoluteTimeGetCurrent()
        guard let resizedImage = imageProcessor.resize(cgImage, maxHeight: maxHeight) else {
            logger.error("Failed to resize image")
            return
        }
        let resizeMs = Int((CFAbsoluteTimeGetCurrent() - resizeStart) * 1000)

        let currentHash = imageProcessor.hash(image: resizedImage)

        let timestamp = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: timestamp)

        // 2. Deduplication check
        if currentHash == lastHash, let fileName = lastFileName {
            logger.info("Image identical to last capture. Deduplicating.")

            let dbStart = CFAbsoluteTimeGetCurrent()
            try await appState.databaseManager.insertSnapshot(
                timestamp: dateString,
                filePath: fileName,
                foregroundApp: foreground.name,
                appBundleId: foreground.bundleIdentifier,
                windowTitle: foreground.windowTitle,
                ocrText: lastOCRText
            )
            let dbMs = Int((CFAbsoluteTimeGetCurrent() - dbStart) * 1000)

            await MainActor.run {
                appState.lastCaptureTime = timestamp
                appState.captureCount += 1
            }

            let totalMs = Int((CFAbsoluteTimeGetCurrent() - pipelineStart) * 1000)
            let metrics = CaptureMetrics(
                captureMs: captureMs, resizeMs: resizeMs, ocrMs: 0,
                compressMs: 0, saveMs: 0, dbMs: dbMs, totalMs: totalMs, deduplicated: true
            )
            logger.debug("\(metrics) — \(foreground.name)")
            return
        }

        // 3. Process concurrently (OCR + Compress)
        let ocrLevelStr = await appState.configuration.ocrRecognitionLevel
        let ocrLevel: VNRequestTextRecognitionLevel = (ocrLevelStr == "fast") ? .fast : .accurate

        let processingStart = CFAbsoluteTimeGetCurrent()
        async let ocrTask = ocrEngine.recognizeText(in: resizedImage, level: ocrLevel)
        async let heicDataTask = Task.detached {
            self.imageProcessor.compressToHEIC(resizedImage, quality: quality)
        }.value

        let (ocrText, heicData) = try await (ocrTask, heicDataTask)
        let ocrAndCompressMs = Int((CFAbsoluteTimeGetCurrent() - processingStart) * 1000)

        guard let heicData = heicData else {
            logger.error("Image processing failed to produce HEIC data")
            return
        }

        // 4. Save to disk
        let saveStart = CFAbsoluteTimeGetCurrent()
        let fileName: String
        do {
            fileName = try appState.screenshotStorage.save(imageData: heicData, hash: currentHash, fileExtension: "heic")
        } catch {
            logger.error("Failed to write image to disk: \(error)")
            return
        }
        let saveMs = Int((CFAbsoluteTimeGetCurrent() - saveStart) * 1000)

        // Update dedup state
        self.lastHash = currentHash
        self.lastFileName = fileName
        self.lastOCRText = ocrText

        // 5. Save to Database
        let dbStart = CFAbsoluteTimeGetCurrent()
        try await appState.databaseManager.insertSnapshot(
            timestamp: dateString,
            filePath: fileName,
            foregroundApp: foreground.name,
            appBundleId: foreground.bundleIdentifier,
            windowTitle: foreground.windowTitle,
            ocrText: ocrText
        )
        let dbMs = Int((CFAbsoluteTimeGetCurrent() - dbStart) * 1000)

        await MainActor.run {
            appState.lastCaptureTime = timestamp
            appState.captureCount += 1
        }

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - pipelineStart) * 1000)
        let metrics = CaptureMetrics(
            captureMs: captureMs,
            resizeMs: resizeMs,
            ocrMs: ocrAndCompressMs,   // OCR and compress run in parallel; report combined
            compressMs: 0,             // Included in ocrMs above (parallel)
            saveMs: saveMs,
            dbMs: dbMs,
            totalMs: totalMs,
            deduplicated: false
        )
        logger.debug("\(metrics) — \(foreground.name)")

        // Warn if pipeline is consuming too much of the capture interval
        let intervalMs = await appState.configuration.captureIntervalSeconds * 1000
        if totalMs > intervalMs / 2 {
            logger.warning("Pipeline took \(totalMs)ms — more than 50% of \(intervalMs)ms interval. Consider increasing the capture interval.")
        }
    }
}
