import CoreGraphics
import UniformTypeIdentifiers
import ImageIO
import Foundation

final class ImageProcessor: Sendable {
    init() {}
    
    /// Resizes the image so its height ≤ maxHeight, maintaining aspect ratio.
    /// Returns the resized CGImage.
    func resize(_ image: CGImage, maxHeight: Int) -> CGImage? {
        let originalWidth = CGFloat(image.width)
        let originalHeight = CGFloat(image.height)
        
        let targetHeight = CGFloat(maxHeight)
        let targetWidth = targetHeight * (16.0 / 9.0)
        
        // If image is already smaller or equal, return original
        if originalHeight <= targetHeight && originalWidth <= targetWidth {
            return image
        }
        
        let scale = min(targetWidth / originalWidth, targetHeight / originalHeight)
        let newWidth = max(1, Int(originalWidth * scale))
        let newHeight = max(1, Int(originalHeight * scale))
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        
        // bitsPerComponent: 8, bytesPerRow: 0 (auto), space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        return context.makeImage()
    }
    
    /// Compresses a CGImage to JPEG data at the given quality.
    func compressToJPEG(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return data as Data
    }
    
    /// Convenience: resize + compress in one call.
    func processForStorage(_ image: CGImage, maxHeight: Int, quality: Double) -> Data? {
        guard let resizedImage = resize(image, maxHeight: maxHeight) else { return nil }
        return compressToJPEG(resizedImage, quality: quality)
    }
}
