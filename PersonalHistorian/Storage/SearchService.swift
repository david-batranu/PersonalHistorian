import Foundation
import GRDB

final class SearchService: Sendable {
    private let dbManager: DatabaseManager?

    init(dbManager: DatabaseManager? = nil) {
        self.dbManager = dbManager
    }

    /// Search snapshots by text query. Returns most recent matches first.
    func search(query: String, limit: Int = 50) throws -> [SnapshotRecord] {
        guard let dbPool = dbManager?.dbPool else { return [] }

        return try dbPool.read { db in
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return try SnapshotRecord
                    .order(Column("timestamp").desc)
                    .limit(limit)
                    .fetchAll(db)
            } else {
                return try Self.ftsSearch(db, query: query, limit: limit)
            }
        }
    }

    /// Search snapshots within a date range, optionally filtered by text query.
    /// - Parameters:
    ///   - query: Full-text search query. If empty, returns all snapshots in the range.
    ///   - from: Start of date range (inclusive).
    ///   - to: End of date range (inclusive).
    ///   - limit: Maximum number of results.
    func search(query: String, from: Date, to: Date, limit: Int = 50) throws -> [SnapshotRecord] {
        guard let dbPool = dbManager?.dbPool else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let fromString = formatter.string(from: from)
        let toString = formatter.string(from: to)

        return try dbPool.read { db in
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return try SnapshotRecord
                    .filter(Column("timestamp") >= fromString && Column("timestamp") <= toString)
                    .order(Column("timestamp").desc)
                    .limit(limit)
                    .fetchAll(db)
            } else {
                let tokens = Self.sanitizedTokens(from: query)
                guard let pattern = FTS5Pattern(matchingAllTokensIn: tokens) else {
                    // Pattern is nil for empty or invalid queries — fall back to range-only
                    return try SnapshotRecord
                        .filter(Column("timestamp") >= fromString && Column("timestamp") <= toString)
                        .order(Column("timestamp").desc)
                        .limit(limit)
                        .fetchAll(db)
                }
                let sql = """
                    SELECT snapshots.*
                    FROM snapshots
                    JOIN snapshots_fts ON snapshots_fts.rowid = snapshots.id
                    WHERE snapshots_fts MATCH ?
                      AND snapshots.timestamp >= ?
                      AND snapshots.timestamp <= ?
                    ORDER BY snapshots.timestamp DESC
                    LIMIT ?
                """
                return try SnapshotRecord.fetchAll(db, sql: sql, arguments: [pattern, fromString, toString, limit])
            }
        }
    }

    /// Get snapshots for a specific app.
    func snapshots(forApp appName: String, limit: Int = 50) throws -> [SnapshotRecord] {
        guard let dbPool = dbManager?.dbPool else { return [] }
        return try dbPool.read { db in
            try SnapshotRecord
                .filter(Column("foregroundApp") == appName)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Private Helpers

    /// Build a prefix-matching FTS5 query and execute it.
    private static func ftsSearch(_ db: Database, query: String, limit: Int) throws -> [SnapshotRecord] {
        let tokens = sanitizedTokens(from: query)
        guard let pattern = FTS5Pattern(matchingAllTokensIn: tokens) else {
            // Pattern is nil for problematic input — return empty
            return []
        }
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

    /// Sanitizes a user query for FTS5 by:
    /// 1. Splitting into tokens on whitespace.
    /// 2. Stripping FTS5 special characters that could cause parse errors.
    /// 3. Appending `*` for prefix matching (e.g. "slac" matches "Slack").
    private static func sanitizedTokens(from query: String) -> String {
        // FTS5 special characters that need to be stripped from tokens
        let ftsSpecialChars = CharacterSet(charactersIn: "\"*^(){}[]\\+-")
        return query
            .split(separator: " ")
            .compactMap { token -> String? in
                let cleaned = String(token)
                    .components(separatedBy: ftsSpecialChars)
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : "\(cleaned)*"
            }
            .joined(separator: " ")
    }
}
