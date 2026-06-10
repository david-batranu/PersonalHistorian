import CoreGraphics
import UniformTypeIdentifiers
import ImageIO
import Foundation
import CryptoKit

final class ImageProcessor: Sendable {
    init() {}
    
    /// Resizes the image so its height ≤ maxHeight, maintaining aspect ratio.
    /// Returns the resized CGImage.
    func resize(_ image: CGImage, maxHeight: Int) -> CGImage? {
        let originalWidth = CGFloat(image.width)
        let originalHeight = CGFloat(image.height)
        
        let targetHeight = CGFloat(maxHeight)
        // Preserve the original aspect ratio — do not assume 16:9
        let aspectRatio = originalWidth / originalHeight
        let targetWidth = targetHeight * aspectRatio
        
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
    
    /// Compresses a CGImage to HEIC data at the given quality.
    func compressToHEIC(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
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
    
    /// Hashes the raw pixel data of the image for deduplication.
    func hash(image: CGImage) -> String {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytePtr = CFDataGetBytePtr(data) else {
            // Fall back to UUID if pixel data is inaccessible
            return UUID().uuidString
        }
        let length = CFDataGetLength(data)
        let imageHash = Insecure.MD5.hash(data: Data(bytes: bytePtr, count: length))
        return imageHash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Convenience: resize + compress in one call. Returns the hash and the data.
    func processForStorage(_ image: CGImage, maxHeight: Int, quality: Double) -> (hash: String, data: Data)? {
        guard let resizedImage = resize(image, maxHeight: maxHeight) else { return nil }
        let imageHash = hash(image: resizedImage)
        guard let heicData = compressToHEIC(resizedImage, quality: quality) else { return nil }
        return (imageHash, heicData)
    }
}
