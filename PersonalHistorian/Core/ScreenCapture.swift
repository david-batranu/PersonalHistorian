import Foundation
import ScreenCaptureKit
import CoreGraphics

enum ScreenCaptureError: Error {
    case permissionDenied
    case noDisplayFound
    case captureFailed(Error)
}

final class ScreenCapture: Sendable {
    /// Checks whether Screen Recording permission has been granted.
    func hasPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }
    
    /// Requests Screen Recording permission (shows system dialog on first call).
    func requestPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }
    
    /// Captures the primary display at native resolution.
    /// Returns the raw CGImage (full Retina resolution).
    func captureMainDisplay() async throws -> CGImage {
        guard hasPermission() else {
            throw ScreenCaptureError.permissionDenied
        }
        
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenCaptureError.captureFailed(error)
        }
        
        guard let display = content.displays.first else {
            throw ScreenCaptureError.noDisplayFound
        }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        
        let config = SCStreamConfiguration()
        config.width = display.width * 2
        config.height = display.height * 2
        config.showsCursor = false
        config.captureResolution = .best
        config.colorSpaceName = CGColorSpace.sRGB
        
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return image
        } catch {
            throw ScreenCaptureError.captureFailed(error)
        }
    }
}
