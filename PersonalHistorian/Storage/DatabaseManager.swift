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
        return migrator
    }
}

