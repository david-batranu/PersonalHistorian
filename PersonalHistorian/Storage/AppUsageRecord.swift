import Foundation
import GRDB

struct AppUsageRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    var date: String // YYYY-MM-DD
    var bundleId: String
    var appName: String
    var durationSeconds: Int
    
    static let databaseTableName = "app_usage"
}
