import XCTest
@testable import PersonalHistorian

final class SearchServiceTests: XCTestCase {
    var dbManager: DatabaseManager!
    var searchService: SearchService!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        let tempUUID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(tempUUID)
        dbManager = DatabaseManager(customAppSupportPath: tempDir.path)
        searchService = SearchService(dbManager: dbManager)
    }
    
    override func tearDown() {
        searchService = nil
        dbManager = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testEmptyQueryReturnsRecent() throws {
        try dbManager.insertSnapshot(timestamp: "2026-06-09 10:00:00", filePath: "1.jpg", foregroundApp: "App1", appBundleId: nil, windowTitle: nil, ocrText: "Text A")
        try dbManager.insertSnapshot(timestamp: "2026-06-09 11:00:00", filePath: "2.jpg", foregroundApp: "App2", appBundleId: nil, windowTitle: nil, ocrText: "Text B")
        
        let results = try searchService.search(query: "")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.foregroundApp, "App2", "Should return newest first")
    }
    
    func testFTS5QueryReturnsMatch() throws {
        try dbManager.insertSnapshot(timestamp: "2026-06-09 10:00:00", filePath: "1.jpg", foregroundApp: "Safari", appBundleId: nil, windowTitle: nil, ocrText: "Looking for a swift developer")
        try dbManager.insertSnapshot(timestamp: "2026-06-09 11:00:00", filePath: "2.jpg", foregroundApp: "Xcode", appBundleId: nil, windowTitle: nil, ocrText: "print(hello)")
        
        let swiftResults = try searchService.search(query: "swift")
        XCTAssertEqual(swiftResults.count, 1)
        XCTAssertEqual(swiftResults.first?.foregroundApp, "Safari")
        
        let xcodeResults = try searchService.search(query: "xcode")
        XCTAssertEqual(xcodeResults.count, 1)
        XCTAssertEqual(xcodeResults.first?.foregroundApp, "Xcode", "FTS5 should match foregroundApp column too")
    }
}
