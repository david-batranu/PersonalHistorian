import Foundation

struct RunningAppInfo: Codable, Hashable, Sendable {
    let name: String
    let bundleIdentifier: String
    let processIdentifier: Int32
    let isForeground: Bool
    var windowTitle: String? = nil
}
