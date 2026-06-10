import Foundation
import GRDB

final class SearchService: Sendable {
    private let dbManager: DatabaseManager?
    
    init(dbManager: DatabaseManager? = nil) {
        self.dbManager = dbManager
    }
    
    func search(query: String, limit: Int = 50) throws -> [SnapshotRecord] {
        guard let dbPool = dbManager?.dbPool else { return [] }
        
        return try dbPool.read { db in
            if query.isEmpty {
                return try SnapshotRecord
                    .order(Column("timestamp").desc)
                    .limit(limit)
                    .fetchAll(db)
            } else {
                // Enable prefix matching for all tokens using *
                let tokens = query.split(separator: " ").map { "\($0)*" }.joined(separator: " ")
                let pattern = FTS5Pattern(matchingAllTokensIn: tokens)
                let sql = """
                    SELECT snapshots.*
                    FROM snapshots
                    JOIN snapshots_fts ON snapshots_fts.rowid = snapshots.id
                    WHERE snapshots_fts MATCH ?
                    ORDER BY snapshots.timestamp DESC
                    LIMIT ?
                """
                return try SnapshotRecord.fetchAll(db, sql: sql, arguments: [pattern, limit])
            }
        }
    }
}
