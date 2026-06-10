import Foundation
import GRDB

struct SnapshotRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Identifiable, Hashable {
    var id: Int64?
    var timestamp: String
    var imagePath: String
    var foregroundApp: String
    var appBundleId: String?
    var windowTitle: String?
    var ocrText: String?
    
    static let databaseTableName = "snapshots"
    
    var screenshotPath: String? { imagePath }
    
    var parsedTimestamp: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: timestamp) ?? Date()
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case imagePath
        case foregroundApp
        case appBundleId
        case windowTitle
        case ocrText
    }
}
