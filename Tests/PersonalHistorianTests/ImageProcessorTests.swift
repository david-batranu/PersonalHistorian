import XCTest
import CoreGraphics
@testable import PersonalHistorian

final class ImageProcessorTests: XCTestCase {
    var processor: ImageProcessor!
    
    override func setUp() {
        super.setUp()
        processor = ImageProcessor()
    }
    
    override func tearDown() {
        processor = nil
        super.tearDown()
    }
    
    func createSolidColorImage(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }
        
        context.setFillColor(CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        return context.makeImage()
    }
    
    func testResizeExtremeAspectRatio() {
        // 4000x1 — extremely wide, 1px tall
        guard let original = createSolidColorImage(width: 4000, height: 1) else {
            XCTFail("Failed to create mock image")
            return
        }

        let resized = processor.resize(original, maxHeight: 1080)
        XCTAssertNotNil(resized)

        // aspectRatio = 4000/1 = 4000; targetWidth = 1080 * 4000 = 4_320_000
        // originalHeight (1) ≤ 1080 AND originalWidth (4000) ≤ targetWidth (4_320_000)
        // → early return: image passes through unchanged at 4000×1
        XCTAssertEqual(resized?.width, 4000)
        XCTAssertEqual(resized?.height, 1)
    }
    
    func testResizeUltrawideConstraint() {
        // 5000x2000 — wider than tall
        guard let original = createSolidColorImage(width: 5000, height: 2000) else {
            XCTFail("Failed to create mock image")
            return
        }

        let resized = processor.resize(original, maxHeight: 1080)
        XCTAssertNotNil(resized)

        // aspectRatio = 5000/2000 = 2.5; targetWidth = 1080 * 2.5 = 2700
        // scale = min(2700/5000, 1080/2000) = min(0.54, 0.54) = 0.54
        // newWidth = Int(5000 * 0.54) = 2700, newHeight = Int(2000 * 0.54) = 1080
        XCTAssertEqual(resized?.width, 2700)
        XCTAssertEqual(resized?.height, 1080)
    }
    
    func testResizeZeroHeightDoesNotCrash() {
        // 40000x2000 — ultra-wide, scaled to maxHeight=1
        guard let original = createSolidColorImage(width: 40000, height: 2000) else {
            XCTFail("Failed to create mock image")
            return
        }

        let resized = processor.resize(original, maxHeight: 1)
        XCTAssertNotNil(resized)

        // aspectRatio = 40000/2000 = 20; targetWidth = 1 * 20 = 20
        // scale = min(20/40000, 1/2000) = min(0.0005, 0.0005) = 0.0005
        // newWidth = max(1, Int(40000 * 0.0005)) = max(1, 20) = 20
        // newHeight = max(1, Int(2000 * 0.0005)) = max(1, 1) = 1
        XCTAssertEqual(resized?.width, 20)
        XCTAssertEqual(resized?.height, 1)
    }
    
    func testResizeVeryThinImageClamp() {
        guard let original = createSolidColorImage(width: 1, height: 2000) else {
            XCTFail("Failed to create mock image")
            return
        }
        
        // Scale down
        let resized = processor.resize(original, maxHeight: 100)
        XCTAssertNotNil(resized)
        
        // Scale = 100 / 2000 = 0.05
        // New width = 1 * 0.05 = 0.05 -> clamped to max(1, 0) -> 1
        XCTAssertEqual(resized?.width, 1)
        XCTAssertEqual(resized?.height, 100)
    }
}
