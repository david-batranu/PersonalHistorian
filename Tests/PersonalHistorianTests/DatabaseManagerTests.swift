import XCTest
import GRDB
@testable import PersonalHistorian

final class DatabaseManagerTests: XCTestCase {
    var dbManager: DatabaseManager!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        let tempUUID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(tempUUID)
        dbManager = DatabaseManager(customAppSupportPath: tempDir.path)
    }
    
    override func tearDown() {
        dbManager = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testDatabaseInitialization() {
        XCTAssertNotNil(dbManager.dbPool, "Database pool should be initialized")
    }
    
    func testInsertAndFetchSnapshot() throws {
        guard let dbPool = dbManager.dbPool else {
            XCTFail("Missing db pool")
            return
        }
        
        try dbManager.insertSnapshot(
            timestamp: "2026-06-09 12:00:00",
            filePath: "test.jpg",
            foregroundApp: "TestApp",
            appBundleId: "com.test.app",
            windowTitle: "Test Window",
            ocrText: "Hello world"
        )
        
        let snapshots = try dbPool.read { db in
            try SnapshotRecord.fetchAll(db)
        }
        
        XCTAssertEqual(snapshots.count, 1)
        let record = snapshots.first!
        XCTAssertEqual(record.timestamp, "2026-06-09 12:00:00")
        XCTAssertEqual(record.imagePath, "test.jpg")
        XCTAssertEqual(record.foregroundApp, "TestApp")
        XCTAssertEqual(record.ocrText, "Hello world")
    }
    
    func testInsertSession() throws {
        // Given
        let bundleId = "com.apple.dt.Xcode"
        let appName = "Xcode"
        
        let formatter = ISO8601DateFormatter()
        let startTime = formatter.date(from: "2026-06-09T10:00:00Z")!
        let endTime = formatter.date(from: "2026-06-09T10:30:00Z")! // 1800 seconds
        
        // When
        try dbManager.insertSession(bundleId: bundleId, appName: appName, windowTitle: nil, startTime: startTime, endTime: endTime)
        
        // Then
        let usage = try dbManager.fetchAppUsage(for: "2026-06-09")
        XCTAssertEqual(usage.count, 1)
        XCTAssertEqual(usage[0].bundleId, bundleId)
        XCTAssertEqual(usage[0].durationSeconds, 1800)
        
        // When inserting another session
        let startTime2 = formatter.date(from: "2026-06-09T11:00:00Z")!
        let endTime2 = formatter.date(from: "2026-06-09T11:15:00Z")! // 900 seconds
        try dbManager.insertSession(bundleId: bundleId, appName: appName, windowTitle: nil, startTime: startTime2, endTime: endTime2)
        
        // Then total duration should be 2700
        let usageUpdated = try dbManager.fetchAppUsage(for: "2026-06-09")
        XCTAssertEqual(usageUpdated[0].durationSeconds, 2700)
    }
}
