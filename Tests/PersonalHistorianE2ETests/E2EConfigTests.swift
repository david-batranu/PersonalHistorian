import XCTest
import AppKit

final class E2EConfigTests: XCTestCase {
    
    var appRunner: AppRunner!
    var configManager: ConfigurationManager!
    var dbValidator: DatabaseValidator!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        appRunner = AppRunner()
        configManager = ConfigurationManager()
        dbValidator = DatabaseValidator()
        
        // Reset state
        configManager.resetConfig()
        try dbValidator.deleteStorageDirectory()
    }
    
    override func tearDownWithError() throws {
        appRunner.terminateApp()
        try super.tearDownWithError()
    }
    
    // MARK: - Tier 1: Nominal Tests
    
    func test_firstLaunch_createsStorageStructure() throws {
        try appRunner.launchApp()
        
        let successDB = waitForCondition(timeout: 5.0) { dbValidator.checkDatabaseExists() }
        XCTAssertTrue(successDB, "First launch should create the database file.")
        
        let successDir = waitForCondition(timeout: 5.0) { dbValidator.checkScreenshotsDirectoryExists() }
        XCTAssertTrue(successDir, "First launch should create the screenshots directory.")
    }
    
    func test_secondLaunch_appendsToExistingDatabase() throws {
        // First launch
        configManager.setAppConfig(key: "isRecording", value: true)
        configManager.setAppConfig(key: "captureIntervalSeconds", value: 1)
        try appRunner.launchApp()
        
        let successFirst = try waitForCondition(timeout: 5.0) { try dbValidator.getSnapshotCount() >= 1 }
        XCTAssertTrue(successFirst)
        appRunner.terminateApp()
        
        let countAfterFirst = try dbValidator.getSnapshotCount()
        
        // Second launch
        try appRunner.launchApp()
        
        let successSecond = try waitForCondition(timeout: 5.0) { try dbValidator.getSnapshotCount() > countAfterFirst }
        XCTAssertTrue(successSecond, "Second launch should append to existing database.")
    }
    
    func test_isRecordingFalse_preventsCapture() throws {
        configManager.setAppConfig(key: "isRecording", value: false)
        configManager.setAppConfig(key: "captureIntervalSeconds", value: 1)
        try appRunner.launchApp()
        
        Thread.sleep(forTimeInterval: 3.0)
        
        let count = try? dbValidator.getSnapshotCount()
        XCTAssertEqual(count ?? 0, 0, "isRecording = false should prevent any captures.")
    }
    
    func test_customInterval_isRespected() throws {
        configManager.setAppConfig(key: "isRecording", value: true)
        configManager.setAppConfig(key: "captureIntervalSeconds", value: 3)
        try appRunner.launchApp()
        
        let startTime = Date()
        let successFirst = try waitForCondition(timeout: 5.0) { try dbValidator.getSnapshotCount() >= 1 }
        XCTAssertTrue(successFirst)
        
        let firstCaptureTime = Date()
        let successSecond = try waitForCondition(timeout: 5.0) { try dbValidator.getSnapshotCount() >= 2 }
        XCTAssertTrue(successSecond)
        let secondCaptureTime = Date()
        
        let interval = secondCaptureTime.timeIntervalSince(firstCaptureTime)
        XCTAssertGreaterThan(interval, 2.0, "Capture interval of 3s should be respected.")
    }
    
    func test_dynamicToggle_isRecording() throws {
        configManager.setAppConfig(key: "isRecording", value: false)
        configManager.setAppConfig(key: "captureIntervalSeconds", value: 1)
        try appRunner.launchApp()
        
        Thread.sleep(forTimeInterval: 2.0)
        let initialCount = (try? dbValidator.getSnapshotCount()) ?? 0
        XCTAssertEqual(initialCount, 0, "No captures initially.")
        
        // Dynamically toggle on
        configManager.setAppConfig(key: "isRecording", value: true)
        
        let successToggled = try waitForCondition(timeout: 5.0) { try dbValidator.getSnapshotCount() > initialCount }
        XCTAssertTrue(successToggled, "Dynamically turning on isRecording should start capture.")
        
        let countAfterToggleOn = try dbValidator.getSnapshotCount()
        
        // Dynamically toggle off
        configManager.setAppConfig(key: "isRecording", value: false)
        Thread.sleep(forTimeInterval: 2.0)
        
        let finalCount = try dbValidator.getSnapshotCount()
        // Allow at most 1 more capture due to race conditions
        XCTAssertLessThanOrEqual(finalCount - countAfterToggleOn, 1, "Dynamically turning off isRecording should stop capture.")
    }
    
    // MARK: - Tier 2: Boundary / Edge Tests
    
    func test_captureInterval_zeroOrNegative_clamps() throws {
        configManager.setAppConfig(key: "isRecording", value: true)
        configManager.setAppConfig(key: "captureIntervalSeconds", value: -5)
        try appRunner.launchApp()
        
        let successFirst = try waitForCondition(timeout: 5.0) { try dbValidator.getSnapshotCount() >= 1 }
        XCTAssertTrue(successFirst, "Negative interval should clamp and not crash.")
        XCTAssertTrue(appRunner.appProcess?.isRunning == true, "App should continue running.")
    }
    
    func test_invalidConfigTypes_fallbackToDefaults() throws {
        configManager.setAppConfig(key: "isRecording", value: "not_a_bool")
        configManager.setAppConfig(key: "captureIntervalSeconds", value: "not_an_int")
        try appRunner.launchApp()
        
        let successFirst = try waitForCondition(timeout: 5.0) { try dbValidator.getSnapshotCount() >= 1 }
        XCTAssertTrue(successFirst, "Invalid config types should fallback to valid defaults.")
    }
    
    func test_corruptedDatabase_onLaunch_recovers() throws {
        try FileManager.default.createDirectory(at: E2EConfig.appSupportURL, withIntermediateDirectories: true)
        let corruptData = Data([0x00, 0x01, 0xFF])
        try corruptData.write(to: E2EConfig.dbURL)
        
        configManager.setAppConfig(key: "isRecording", value: true)
        configManager.setAppConfig(key: "captureIntervalSeconds", value: 1)
        try appRunner.launchApp()
        
        let success = try waitForCondition(timeout: 5.0) { try dbValidator.getSnapshotCount() >= 1 }
        XCTAssertTrue(success, "Should recover from corrupted database and create new valid db.")
    }
    
    func test_readOnlyStorageDirectory_handlesGracefully() throws {
        try FileManager.default.createDirectory(at: E2EConfig.appSupportURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: E2EConfig.appSupportURL.path)
        
        configManager.setAppConfig(key: "isRecording", value: true)
        configManager.setAppConfig(key: "captureIntervalSeconds", value: 1)
        try appRunner.launchApp()
        
        Thread.sleep(forTimeInterval: 3.0)
        XCTAssertTrue(appRunner.appProcess?.isRunning == true, "App should handle read-only storage directory gracefully without crashing.")
        
        // Revert permissions to allow cleanup
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: E2EConfig.appSupportURL.path)
    }
    
    func test_deletedScreenshotsDirectory_midRun() throws {
        configManager.setAppConfig(key: "isRecording", value: true)
        configManager.setAppConfig(key: "captureIntervalSeconds", value: 1)
        try appRunner.launchApp()
        
        let successFirst = waitForCondition(timeout: 5.0) { dbValidator.checkScreenshotsDirectoryExists() }
        XCTAssertTrue(successFirst)
        
        try FileManager.default.removeItem(at: E2EConfig.screenshotsURL)
        
        let successRecreated = waitForCondition(timeout: 5.0) { dbValidator.checkScreenshotsDirectoryExists() }
        XCTAssertTrue(successRecreated, "Deleting screenshots directory mid-run should be handled, directory recreated.")
    }
    
    // MARK: - Tier 3: Interactions
    
    func test_rapid_isRecording_toggles() throws {
        try appRunner.launchApp()
        
        for i in 0..<10 {
            let value = i % 2 == 0
            configManager.setAppConfig(key: "isRecording", value: value)
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        XCTAssertTrue(appRunner.appProcess?.isRunning == true, "Rapid toggling should not crash the app.")
    }
    
    func test_startup_withPendingRetentionCleanup() throws {
        // Setup mock old data to trigger cleanup on startup
        try FileManager.default.createDirectory(at: E2EConfig.screenshotsURL, withIntermediateDirectories: true)
        let initSchema = "CREATE TABLE IF NOT EXISTS snapshots(id INTEGER PRIMARY KEY, timestamp DATETIME, filePath TEXT, foregroundApp TEXT, textContent TEXT);"
        _ = try dbValidator.executeSQLite(query: initSchema)
        
        let oldDate = Date().addingTimeInterval(-30 * 24 * 3600) // 30 days ago
        let formatter = ISO8601DateFormatter()
        let oldDateStr = formatter.string(from: oldDate)
        
        let insert = "INSERT INTO snapshots (timestamp, filePath, foregroundApp) VALUES ('\(oldDateStr)', 'old.jpg', 'com.apple.Safari');"
        _ = try dbValidator.executeSQLite(query: insert)
        let oldImageURL = E2EConfig.screenshotsURL.appendingPathComponent("old.jpg")
        FileManager.default.createFile(atPath: oldImageURL.path, contents: Data())
        
        configManager.setAppConfig(key: "retentionDays", value: 7)
        configManager.setAppConfig(key: "isRecording", value: false)
        
        try appRunner.launchApp()
        
        let successCleanup = waitForCondition(timeout: 5.0) {
            !FileManager.default.fileExists(atPath: oldImageURL.path)
        }
        XCTAssertTrue(successCleanup, "Old screenshot file should be deleted on startup.")
        
        let count = try dbValidator.executeSQLite(query: "SELECT count(*) FROM snapshots WHERE filePath = 'old.jpg';")
        XCTAssertEqual(count, "0", "Old database row should be deleted on startup.")
    }
}
