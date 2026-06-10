import XCTest
import CoreGraphics
import AppKit
@testable import PersonalHistorian

final class OCREngineTests: XCTestCase {
    var ocrEngine: OCREngine!
    
    override func setUp() {
        super.setUp()
        ocrEngine = OCREngine()
    }
    
    override func tearDown() {
        ocrEngine = nil
        super.tearDown()
    }
    
    private func createTextImage(text: String) -> CGImage {
        let size = NSSize(width: 800, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        
        NSColor.white.set()
        NSRect(origin: .zero, size: size).fill()
        
        let attrString = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 48),
            .foregroundColor: NSColor.black
        ])
        attrString.draw(at: NSPoint(x: 20, y: 50))
        
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
    
    func testOCRRecognition() async throws {
        let textToRecognize = "Personal Historian OCR Test"
        let image = createTextImage(text: textToRecognize)
        
        let recognizedText = try await ocrEngine.recognizeText(in: image, level: .accurate)
        
        // The OCR might output "Personal Historian OCR Test" or similar variations depending on Vision's exact output.
        // But it should definitely contain our main keywords.
        XCTAssertTrue(recognizedText.contains("Personal"), "Expected 'Personal' in \(recognizedText)")
        XCTAssertTrue(recognizedText.contains("Historian"), "Expected 'Historian' in \(recognizedText)")
    }
}
