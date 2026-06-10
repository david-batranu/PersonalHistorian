import Foundation
import GRDB
import OSLog

final class DatabaseManager: Sendable {
    let dbPool: DatabasePool?
    
    init(customAppSupportPath: String? = nil) {
        let fileManager = FileManager.default
        let appSupportURL: URL
        if let custom = customAppSupportPath {
            appSupportURL = URL(fileURLWithPath: custom)
        } else {
            appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("com.personalhistorian.app")
        }
        
        do {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            let dbURL = appSupportURL.appendingPathComponent("historian.db")
            
            var pool: DatabasePool
            do {
                pool = try DatabasePool(path: dbURL.path)
                try Self.migrator.migrate(pool)
            } catch {
                // Recover from corruption or not-a-database errors
                try? fileManager.removeItem(at: dbURL)
                let walURL = appSupportURL.appendingPathComponent("historian.db-wal")
                let shmURL = appSupportURL.appendingPathComponent("historian.db-shm")
                try? fileManager.removeItem(at: walURL)
                try? fileManager.removeItem(at: shmURL)
                
                pool = try DatabasePool(path: dbURL.path)
                try Self.migrator.migrate(pool)
            }
            self.dbPool = pool
        } catch {
            print("Failed to initialize database: \(error)")
            self.dbPool = nil
        }
    }
    
    func insertSnapshot(timestamp: String, filePath: String, foregroundApp: String, appBundleId: String?, windowTitle: String?, ocrText: String?) throws {
        try dbPool?.write { db in
            try db.execute(sql: """
                INSERT INTO snapshots (timestamp, imagePath, foregroundApp, appBundleId, windowTitle, ocrText)
                VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [timestamp, filePath, foregroundApp, appBundleId, windowTitle, ocrText])
        }
    }
    
    func insertSession(bundleId: String, appName: String, windowTitle: String?, startTime: Date, endTime: Date) throws {
        try dbPool?.write { db in
            try db.execute(sql: """
                INSERT INTO usage_sessions (bundleId, appName, windowTitle, startTime, endTime)
                VALUES (?, ?, ?, ?, ?)
            """, arguments: [bundleId, appName, windowTitle, startTime, endTime])
        }
    }
    
    func fetchAppUsage(for dateString: String) throws -> [AppUsageRecord] {
        // Aggregate sessions for the given date
        guard let dbPool = dbPool else { return [] }
        return try dbPool.read { db in
            let sql = """
                SELECT date(startTime, 'localtime') as date, bundleId, appName, windowTitle, SUM(CAST((strftime('%s', endTime) - strftime('%s', startTime)) AS INTEGER)) as durationSeconds
                FROM usage_sessions
                WHERE date(startTime, 'localtime') = ?
                GROUP BY bundleId, appName, windowTitle
                ORDER BY durationSeconds DESC
            """
            return try AppUsageRecord.fetchAll(db, sql: sql, arguments: [dateString])
        }
    }
    
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "snapshots") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull()
                t.column("imagePath", .text).notNull()
                t.column("foregroundApp", .text).notNull()
                t.column("appBundleId", .text)
                t.column("windowTitle", .text)
                t.column("ocrText", .text)
            }
            
            try db.create(virtualTable: "snapshots_fts", using: FTS5()) { t in
                t.synchronize(withTable: "snapshots")
                t.column("ocrText")
                t.column("windowTitle")
                t.column("foregroundApp")
            }
        }
        
        migrator.registerMigration("v2") { db in
            try db.create(table: "app_usage") { t in
                t.column("date", .text).notNull()
                t.column("appName", .text).notNull()
                t.column("bundleId", .text).notNull()
                t.column("durationSeconds", .integer).notNull().defaults(to: 0)
                t.primaryKey(["date", "bundleId"])
            }
        }
        
        migrator.registerMigration("v3") { db in
            try db.create(index: "idx_snapshots_timestamp", on: "snapshots", columns: ["timestamp"])
            try db.create(index: "idx_snapshots_bundleId", on: "snapshots", columns: ["appBundleId"])
        }
        
        migrator.registerMigration("v4") { db in
            try db.create(table: "usage_sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bundleId", .text).notNull()
                t.column("appName", .text).notNull()
                t.column("startTime", .datetime).notNull()
                t.column("endTime", .datetime).notNull()
            }
        }
        
        migrator.registerMigration("v5") { db in
            try db.alter(table: "usage_sessions") { t in
                t.add(column: "windowTitle", .text)
            }
        }
        
        return migrator
    }
}

