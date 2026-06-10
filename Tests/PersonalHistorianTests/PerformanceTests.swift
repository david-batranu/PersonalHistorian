import XCTest
import CoreGraphics
import AppKit
@testable import PersonalHistorian

final class PerformanceTests: XCTestCase {
    var ocrEngine: OCREngine!
    var imageProcessor: ImageProcessor!
    var sampleImage: CGImage!
    
    override func setUp() {
        super.setUp()
        ocrEngine = OCREngine()
        imageProcessor = ImageProcessor()
        sampleImage = createTextImage(text: "Performance Benchmark Test\nWith multiple lines\nTo simulate realistic OCR workloads.")
    }
    
    override func tearDown() {
        ocrEngine = nil
        imageProcessor = nil
        sampleImage = nil
        super.tearDown()
    }
    
    private func createTextImage(text: String) -> CGImage {
        let size = NSSize(width: 3840, height: 2160)
        let image = NSImage(size: size)
        image.lockFocus()
        
        NSColor.white.set()
        NSRect(origin: .zero, size: size).fill()
        
        let attrString = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 72),
            .foregroundColor: NSColor.black
        ])
        attrString.draw(at: NSPoint(x: 200, y: 200))
        
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
    
    func testOCRPerformanceFast() {
        measure {
            let exp = expectation(description: "ocr")
            Task {
                _ = try? await ocrEngine.recognizeText(in: sampleImage, level: .fast)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5.0)
        }
    }
    
    func testOCRPerformanceAccurate() {
        measure {
            let exp = expectation(description: "ocr")
            Task {
                _ = try? await ocrEngine.recognizeText(in: sampleImage, level: .accurate)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5.0)
        }
    }
    
    func testImageProcessingPerformance() {
        measure {
            _ = imageProcessor.processForStorage(sampleImage, maxHeight: 1080, quality: 0.7)
        }
    }
}
