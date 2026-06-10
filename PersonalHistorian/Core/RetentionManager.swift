import Foundation
import OSLog
import GRDB

final class RetentionManager: Sendable {
    private let dbManager: DatabaseManager
    private let storage: ScreenshotStorage
    private let logger = Logger(subsystem: "com.personalhistorian.app", category: "RetentionManager")
    
    // Retention period in seconds (30 days)
    private let retentionPeriod: TimeInterval = 30 * 24 * 60 * 60
    
    init(dbManager: DatabaseManager, storage: ScreenshotStorage) {
        self.dbManager = dbManager
        self.storage = storage
    }
    
    func cleanOldData() async {
        logger.info("Starting retention cleanup")
        let cutoffDate = Date().addingTimeInterval(-retentionPeriod)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let cutoffString = dateFormatter.string(from: cutoffDate)
        
        guard let pool = dbManager.dbPool else { return }
        
        do {
            // 1. Fetch old snapshots to delete files
            let pathsToDelete: [String] = try await pool.read { db in
                let sql = "SELECT imagePath FROM snapshots WHERE timestamp < ?"
                return try String.fetchAll(db, sql: sql, arguments: [cutoffString])
            }
            
            // 2. Delete files from disk
            for path in pathsToDelete {
                try? storage.delete(fileName: path)
            }
            
            // 3. Delete rows from DB
            try await pool.write { db in
                try db.execute(sql: "DELETE FROM snapshots WHERE timestamp < ?", arguments: [cutoffString])
                
                // Cleanup old sessions
                let isoFormatter = ISO8601DateFormatter()
                let isoCutoff = isoFormatter.string(from: cutoffDate)
                try db.execute(sql: "DELETE FROM usage_sessions WHERE endTime < ?", arguments: [isoCutoff])
            }
            
            logger.info("Retention cleanup finished. Deleted \(pathsToDelete.count) snapshots.")
        } catch {
            logger.error("Retention cleanup failed: \(error)")
        }
    }
}
