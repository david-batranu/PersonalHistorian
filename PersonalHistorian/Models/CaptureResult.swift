import Foundation
import CoreGraphics

struct CaptureResult: Sendable {
    let timestamp: Date
    let screenshot: CGImage
    let foregroundApp: RunningAppInfo
    let runningApps: [RunningAppInfo]
    let ocrText: String
}
