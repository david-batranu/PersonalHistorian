import Foundation
import OSLog
import GRDB

final class RetentionManager: Sendable {
    private let dbManager: DatabaseManager
    private let storage: ScreenshotStorage
    private let configuration: Configuration
    private let logger = Logger(subsystem: "com.personalhistorian.app", category: "RetentionManager")

    init(dbManager: DatabaseManager, storage: ScreenshotStorage, configuration: Configuration) {
        self.dbManager = dbManager
        self.storage = storage
        self.configuration = configuration
    }

    func cleanOldData() async {
        let retentionDays = configuration.retentionDays
        // retentionDays == 0 means keep forever — skip cleanup
        guard retentionDays > 0 else {
            logger.info("Retention cleanup skipped: retentionDays is 0 (keep forever)")
            return
        }

        logger.info("Starting retention cleanup (retentionDays: \(retentionDays))")
        let retentionPeriod: TimeInterval = Double(retentionDays) * 24 * 60 * 60
        let cutoffDate = Date().addingTimeInterval(-retentionPeriod)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let cutoffString = dateFormatter.string(from: cutoffDate)

        guard let pool = dbManager.dbPool else { return }

        do {
            // 1. Delete rows from DB
            try await pool.write { db in
                try db.execute(sql: "DELETE FROM snapshots WHERE timestamp < ?", arguments: [cutoffString])

                // Cleanup old sessions
                let isoFormatter = ISO8601DateFormatter()
                let isoCutoff = isoFormatter.string(from: cutoffDate)
                try db.execute(sql: "DELETE FROM usage_sessions WHERE endTime < ?", arguments: [isoCutoff])
            }

            // 2. Fetch ALL remaining referenced image paths
            let activePaths: Set<String> = try await pool.read { db in
                let sql = "SELECT DISTINCT imagePath FROM snapshots"
                let paths = try String.fetchAll(db, sql: sql)
                return Set(paths)
            }

            // 3. Scan the storage directory and delete unreferenced files
            let allFiles = try FileManager.default.contentsOfDirectory(atPath: storage.baseDirectory.path)
            var deletedCount = 0
            for file in allFiles {
                if !activePaths.contains(file) {
                    try? storage.delete(fileName: file)
                    deletedCount += 1
                }
            }

            logger.info("Retention cleanup finished. Deleted \(deletedCount) unreferenced files.")
        } catch {
            logger.error("Retention cleanup failed: \(error)")
        }
    }
}
