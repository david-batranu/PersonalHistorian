import XCTest
import CoreGraphics
import AppKit
import Vision
@testable import PersonalHistorian

final class IntegrationTests: XCTestCase {
    var dbManager: DatabaseManager!
    var storage: ScreenshotStorage!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        let tempUUID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(tempUUID)
        dbManager = DatabaseManager(customAppSupportPath: tempDir.path)
        storage = ScreenshotStorage()
    }
    
    override func tearDown() {
        dbManager = nil
        storage = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    private func createTextImage(text: String) -> CGImage {
        let size = NSSize(width: 1920, height: 1080)
        let image = NSImage(size: size)
        image.lockFocus()
        
        NSColor.white.set()
        NSRect(origin: .zero, size: size).fill()
        
        let attrString = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 48),
            .foregroundColor: NSColor.black
        ])
        attrString.draw(at: NSPoint(x: 100, y: 100))
        
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
    
    func testFullPipeline() async throws {
        let ocrEngine = OCREngine()
        let imageProcessor = ImageProcessor()
        
        let sampleImage = createTextImage(text: "Pipeline Integration Test")
        
        async let ocrTask = ocrEngine.recognizeText(in: sampleImage, level: .accurate)
        async let processTask = Task.detached {
            imageProcessor.processForStorage(sampleImage, maxHeight: 1080, quality: 0.7)
        }.value
        
        let (ocrText, processResult) = try await (ocrTask, processTask)

        XCTAssertNotNil(processResult)
        XCTAssertTrue(ocrText.contains("Pipeline"))
        XCTAssertTrue(ocrText.contains("Integration"))

        guard let processResult = processResult else {
            XCTFail("processForStorage should return a non-nil result")
            return
        }

        let fileId = processResult.hash
        let fileName = "\(fileId).heic"
        let fileUrl = tempDir.appendingPathComponent("Screenshots").appendingPathComponent(fileName)

        // Create directory since we use custom path
        try FileManager.default.createDirectory(at: fileUrl.deletingLastPathComponent(), withIntermediateDirectories: true)

        try processResult.data.write(to: fileUrl, options: .atomic)
        
        try dbManager.insertSnapshot(
            timestamp: "2026-06-09 13:00:00",
            filePath: fileName,
            foregroundApp: "Xcode",
            appBundleId: "com.apple.dt.Xcode",
            windowTitle: nil,
            ocrText: ocrText
        )
        
        // Verify via search
        let searchService = SearchService(dbManager: dbManager)
        let results = try searchService.search(query: "Integration")
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.foregroundApp, "Xcode")
        XCTAssertEqual(results.first?.imagePath, fileName)
    }
}
