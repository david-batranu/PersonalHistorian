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
        // 4000x1
        guard let original = createSolidColorImage(width: 4000, height: 1) else {
            XCTFail("Failed to create mock image")
            return
        }
        
        let resized = processor.resize(original, maxHeight: 1080)
        XCTAssertNotNil(resized)
        
        // With unbounded width fix, an image that is 4000x1 will have target width 1920.
        // Scale = 1920 / 4000 = 0.48. New width = 1920, new height = max(1, 1 * 0.48) = 1.
        XCTAssertEqual(resized?.width, 1920)
        XCTAssertEqual(resized?.height, 1)
    }
    
    func testResizeUltrawideConstraint() {
        // Create an image that is taller than max height to force a resize
        // e.g. 5000 x 2000
        guard let original = createSolidColorImage(width: 5000, height: 2000) else {
            XCTFail("Failed to create mock image")
            return
        }
        
        let resized = processor.resize(original, maxHeight: 1080)
        XCTAssertNotNil(resized)
        
        // Scale should be min(1920/5000, 1080/2000) = 0.384
        // New width = 5000 * 0.384 = 1920
        // New height = 2000 * 0.384 = 768
        XCTAssertEqual(resized?.width, 1920)
        XCTAssertEqual(resized?.height, 768)
    }
    
    func testResizeZeroHeightDoesNotCrash() {
        // Technically an image cannot have zero height, but let's test a very thin one that requires scale down
        guard let original = createSolidColorImage(width: 40000, height: 2000) else {
            XCTFail("Failed to create mock image")
            return
        }
        
        // Scale down significantly
        let resized = processor.resize(original, maxHeight: 1)
        XCTAssertNotNil(resized)
        
        // Scale = min(1.777/40000, 1/2000) = 0.0000444
        // New width = 40000 * 0.0000444 = 1.77 -> 1
        XCTAssertEqual(resized?.width, 1)
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
