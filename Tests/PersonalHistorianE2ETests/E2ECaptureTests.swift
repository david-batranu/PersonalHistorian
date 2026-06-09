import XCTest
import AppKit

final class E2ECaptureTests: XCTestCase {

    var appProcess: Process?
    let bundleID = "com.personalhistorian.app"
    
    var appSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(bundleID)
    }
    
    var dbURL: URL {
        appSupportURL.appendingPathComponent("historian.db")
    }
    
    var screenshotsURL: URL {
        appSupportURL.appendingPathComponent("screenshots")
    }
    
    var defaults: UserDefaults {
        UserDefaults(suiteName: "com.personalhistorian.prefs") ?? .standard
    }
    
    var appExecutableURL: URL {
        return E2EConfig.appExecutableURL
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        E2EConfig.currentTestID = UUID().uuidString
        
        // Ensure clean state before each test
        if FileManager.default.fileExists(atPath: appSupportURL.path) {
            try FileManager.default.removeItem(at: appSupportURL)
        }
        
        // Clear UserDefaults
        defaults.removePersistentDomain(forName: "com.personalhistorian.prefs")
        defaults.synchronize()
    }

    override func tearDownWithError() throws {
        terminateApp()
        
        if FileManager.default.fileExists(atPath: appSupportURL.path) {
            // Un-comment to clean up after tests, but sometimes helpful to keep for debugging
            // try FileManager.default.removeItem(at: appSupportURL)
        }
        
        try super.tearDownWithError()
    }
    
    // MARK: - Helpers
    
    private func launchApp(captureEnabled: Bool = true, interval: Int = 1) throws {
        defaults.set(captureEnabled, forKey: "isRecording")
        defaults.set(interval, forKey: "captureIntervalSeconds")
        defaults.set(appSupportURL.path, forKey: "testAppSupportDir")
        defaults.synchronize()
        
        let process = Process()
        process.executableURL = appExecutableURL
        try process.run()
        appProcess = process
        
        // Give the app time to initialize the database and perform migrations before we start polling with sqlite3
        Thread.sleep(forTimeInterval: 1.5)
    }
    
    private func terminateApp() {
        if let process = appProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        appProcess = nil
    }
    
    private func executeSQLite(query: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [dbURL.path, query]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    private func getDBRowCount() throws -> Int {
        let result = try executeSQLite(query: "SELECT count(*) FROM snapshots;")
        return Int(result) ?? 0
    }
    
    private func waitForCondition(timeout: TimeInterval = 5.0, pollInterval: TimeInterval = 0.5, condition: () throws -> Bool) rethrows -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if try condition() {
                return true
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return false
    }

    // MARK: - Tier 1: Category-Partition (Happy Paths)
    
    func testCaptureAndStorage_StandardInterval() throws {
        try launchApp(captureEnabled: true, interval: 1)
        
        let success = try waitForCondition(timeout: 5.0) {
            let rowCount = try getDBRowCount()
            return rowCount >= 2
        }
        
        XCTAssertTrue(success, "Expected at least 2 captures in database")
        
        let files = try FileManager.default.contentsOfDirectory(atPath: screenshotsURL.path)
        let imageFiles = files.filter { $0.hasSuffix(".jpg") || $0.hasSuffix(".png") }
        XCTAssertGreaterThanOrEqual(imageFiles.count, 2, "Expected at least 2 screenshots in directory")
    }
    
    func testCaptureDisabled_NoFilesCreated() throws {
        try launchApp(captureEnabled: false, interval: 1)
        
        // Wait a bit to ensure it doesn't capture
        Thread.sleep(forTimeInterval: 3.0)
        
        let rowCount = try? getDBRowCount()
        XCTAssertEqual(rowCount, 0, "Expected 0 captures in database when disabled")
        
        let directoryExists = FileManager.default.fileExists(atPath: screenshotsURL.path)
        if directoryExists {
            let files = try FileManager.default.contentsOfDirectory(atPath: screenshotsURL.path)
            XCTAssertTrue(files.isEmpty, "Expected no screenshots when disabled")
        }
    }
    
    func testStorageDirectory_AutoCreated() throws {
        // App support is already deleted in setUpWithError
        XCTAssertFalse(FileManager.default.fileExists(atPath: screenshotsURL.path))
        
        try launchApp(captureEnabled: true, interval: 1)
        
        let success = waitForCondition(timeout: 5.0) {
            FileManager.default.fileExists(atPath: screenshotsURL.path)
        }
        
        XCTAssertTrue(success, "App should auto-create screenshots directory")
        
        let capturesSuccess = try waitForCondition(timeout: 5.0) {
            let files = try FileManager.default.contentsOfDirectory(atPath: screenshotsURL.path)
            return files.count >= 1
        }
        XCTAssertTrue(capturesSuccess, "App should successfully save captures to auto-created directory")
    }
    
    func testDatabaseFile_AutoCreated() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbURL.path))
        
        try launchApp(captureEnabled: true, interval: 1)
        
        let success = waitForCondition(timeout: 5.0) {
            FileManager.default.fileExists(atPath: dbURL.path)
        }
        
        XCTAssertTrue(success, "App should auto-create database file")
        
        let schemaValid = try waitForCondition(timeout: 5.0) {
            let tables = try executeSQLite(query: "SELECT name FROM sqlite_master WHERE type='table' AND name='snapshots';")
            return tables.contains("snapshots")
        }
        XCTAssertTrue(schemaValid, "App should apply database schema on creation")
    }
    
    func testDatabase_StoresCorrectMetadata() throws {
        try launchApp(captureEnabled: true, interval: 1)
        
        let success = try waitForCondition(timeout: 5.0) {
            return try getDBRowCount() >= 1
        }
        XCTAssertTrue(success, "Expected at least 1 row in DB")
        
        let meta = try executeSQLite(query: "SELECT timestamp, imagePath, foregroundApp FROM snapshots LIMIT 1;")
        let columns = meta.components(separatedBy: "|")
        XCTAssertEqual(columns.count, 3, "Expected 3 columns: timestamp, filePath, foregroundApp")
        
        // Verify types and non-emptiness roughly
        XCTAssertFalse(columns[0].isEmpty, "Timestamp should not be empty")
        XCTAssertFalse(columns[1].isEmpty, "FilePath should not be empty")
    }

    // MARK: - Tier 2: Boundary Value Analysis
    
    func testCapture_MinimumInterval() throws {
        // Interval = 1 second
        try launchApp(captureEnabled: true, interval: 1)
        
        let success = try waitForCondition(timeout: 4.0) {
            return try getDBRowCount() >= 2
        }
        XCTAssertTrue(success, "App should handle minimum interval without crashing and produce captures")
        XCTAssertTrue(appProcess?.isRunning == true, "App should not crash with minimum interval")
    }
    
    func testStorage_DirectoryReadOnly() throws {
        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
        
        // Set permissions to 444 (read-only)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: screenshotsURL.path)
        
        try launchApp(captureEnabled: true, interval: 1)
        
        // Wait and check if app crashes
        Thread.sleep(forTimeInterval: 3.0)
        XCTAssertTrue(appProcess?.isRunning == true, "App should not crash when screenshot directory is read-only")
        
        // Revert permissions so teardown can delete the directory
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: screenshotsURL.path)
    }
    
    func testStorage_DatabaseReadOnly() throws {
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dbURL.path, contents: nil)
        
        // Set permissions to 444 (read-only)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: dbURL.path)
        
        try launchApp(captureEnabled: true, interval: 1)
        
        Thread.sleep(forTimeInterval: 3.0)
        XCTAssertTrue(appProcess?.isRunning == true, "App should not crash when database file is read-only")
        
        // Revert permissions for teardown
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dbURL.path)
    }
    
    func testCapture_HighResolutionSize() throws {
        try launchApp(captureEnabled: true, interval: 1)
        
        let success = waitForCondition(timeout: 5.0) {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: screenshotsURL.path)) ?? []
            return !files.isEmpty
        }
        XCTAssertTrue(success, "Should have captured at least one screenshot")
        
        let files = try FileManager.default.contentsOfDirectory(atPath: screenshotsURL.path)
        let firstImageURL = screenshotsURL.appendingPathComponent(files.first!)
        
        let attrs = try FileManager.default.attributesOfItem(atPath: firstImageURL.path)
        let fileSize = attrs[.size] as? UInt64 ?? 0
        XCTAssertGreaterThan(fileSize, 0, "Screenshot file should not be 0 bytes")
        
        let image = NSImage(contentsOf: firstImageURL)
        XCTAssertNotNil(image, "Should be able to load saved screenshot as NSImage")
        if let image = image {
            XCTAssertGreaterThan(image.size.width, 0, "Image width should be greater than 0")
            XCTAssertGreaterThan(image.size.height, 0, "Image height should be greater than 0")
        }
    }
    
    func testStorage_DiskSpaceSimulation() throws {
        // Simulating low disk space in E2E is hard without a mock. 
        // We will simulate it by injecting a user default that forces the app to think disk is full if possible,
        // or just verify that if saving fails (e.g. read-only parent), it handles it gracefully.
        
        // Create an un-writeable app support directory to simulate IO failure
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: appSupportURL.path)
        
        try launchApp(captureEnabled: true, interval: 1)
        
        Thread.sleep(forTimeInterval: 3.0)
        XCTAssertTrue(appProcess?.isRunning == true, "App should not crash on severe IO errors like low disk space/permissions")
        
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appSupportURL.path)
    }

    // MARK: - Tier 3: Pairwise Interactions
    
    func testCaptureAndRestart_AppendStorage() throws {
        // Run first time
        try launchApp(captureEnabled: true, interval: 1)
        var success = try waitForCondition(timeout: 5.0) { try getDBRowCount() >= 2 }
        XCTAssertTrue(success)
        
        terminateApp()
        let countAfterFirstRun = try getDBRowCount()
        
        // Run second time
        try launchApp(captureEnabled: true, interval: 1)
        success = try waitForCondition(timeout: 5.0) { try getDBRowCount() >= countAfterFirstRun + 2 }
        XCTAssertTrue(success, "App should append to existing database and not overwrite")
        
        let files = try FileManager.default.contentsOfDirectory(atPath: screenshotsURL.path)
        XCTAssertGreaterThanOrEqual(files.count, countAfterFirstRun + 2, "Screenshots should also append")
    }
    
    func testCaptureAndRetentionLimit() throws {
        // Let the app initialize the database schema naturally
        try launchApp(captureEnabled: true, interval: 1000)
        let schemaValid = try waitForCondition(timeout: 5.0) {
            if !FileManager.default.fileExists(atPath: dbURL.path) { return false }
            return try executeSQLite(query: "SELECT name FROM sqlite_master WHERE type='table' AND name='snapshots';").contains("snapshots")
        }
        XCTAssertTrue(schemaValid, "App should create the database schema")
        terminateApp()
        
        // Setup mock old data
        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
        
        let oldDateFormatter = ISO8601DateFormatter()
        let oldDate = Date().addingTimeInterval(-30 * 24 * 3600) // 30 days ago
        let oldDateString = oldDateFormatter.string(from: oldDate)
        
        let insertOldRow = "INSERT INTO snapshots (timestamp, filePath, foregroundApp) VALUES ('\(oldDateString)', 'old_screenshot.jpg', 'com.apple.Safari');"
        _ = try executeSQLite(query: insertOldRow)
        
        let oldImageURL = screenshotsURL.appendingPathComponent("old_screenshot.jpg")
        FileManager.default.createFile(atPath: oldImageURL.path, contents: Data([0x00]))
        
        // Set retention to 7 days
        defaults.set(7, forKey: "retentionDays")
        
        // Launch app again to trigger retention logic
        try launchApp(captureEnabled: true, interval: 1)
        
        // Wait for retention cleanup to trigger
        let success = waitForCondition(timeout: 5.0) {
            !FileManager.default.fileExists(atPath: oldImageURL.path)
        }
        XCTAssertTrue(success, "App should delete old screenshots based on retention limit")
        
        let oldRowExists = try executeSQLite(query: "SELECT count(*) FROM snapshots WHERE filePath = 'old_screenshot.jpg';")
        XCTAssertEqual(oldRowExists, "0", "App should delete old DB rows based on retention limit")
    }
    
    func testCaptureWithOCRDisabled() throws {
        defaults.set(false, forKey: "isOCREnabled")
        try launchApp(captureEnabled: true, interval: 1)
        
        let success = try waitForCondition(timeout: 5.0) { try getDBRowCount() >= 1 }
        XCTAssertTrue(success)
        
        let rowData = try executeSQLite(query: "SELECT textContent FROM snapshots LIMIT 1;")
        // Because OCR is disabled, textContent should be empty/null
        XCTAssertTrue(rowData.isEmpty || rowData == "NULL" || rowData == "", "textContent should be empty when OCR is disabled")
    }
    
    func testCaptureWithQualitySettings() throws {
        // Run with low quality
        defaults.set(0.1, forKey: "compressionQuality")
        try launchApp(captureEnabled: true, interval: 1)
        let successLow = waitForCondition(timeout: 5.0) { (try? FileManager.default.contentsOfDirectory(atPath: screenshotsURL.path))?.isEmpty == false }
        XCTAssertTrue(successLow)
        terminateApp()
        
        let filesLow = try FileManager.default.contentsOfDirectory(atPath: screenshotsURL.path)
        let lowImageURL = screenshotsURL.appendingPathComponent(filesLow.first!)
        let attrsLow = try FileManager.default.attributesOfItem(atPath: lowImageURL.path)
        let sizeLow = attrsLow[.size] as? UInt64 ?? 0
        
        // Clear for next run
        try FileManager.default.removeItem(at: screenshotsURL)
        try FileManager.default.removeItem(at: dbURL)
        
        // Run with high quality
        defaults.set(1.0, forKey: "compressionQuality")
        try launchApp(captureEnabled: true, interval: 1)
        let successHigh = waitForCondition(timeout: 5.0) { (try? FileManager.default.contentsOfDirectory(atPath: screenshotsURL.path))?.isEmpty == false }
        XCTAssertTrue(successHigh)
        
        let filesHigh = try FileManager.default.contentsOfDirectory(atPath: screenshotsURL.path)
        let highImageURL = screenshotsURL.appendingPathComponent(filesHigh.first!)
        let attrsHigh = try FileManager.default.attributesOfItem(atPath: highImageURL.path)
        let sizeHigh = attrsHigh[.size] as? UInt64 ?? 0
        
        XCTAssertGreaterThan(sizeHigh, sizeLow, "High quality screenshot should have a larger file size than low quality")
    }
    
    func testDatabase_CorruptFileRecovery() throws {
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        
        // Create corrupt database file
        let randomGarbage = Data((0..<1024).map { _ in UInt8.random(in: 0...255) })
        try randomGarbage.write(to: dbURL)
        
        try launchApp(captureEnabled: true, interval: 1)
        
        let success = waitForCondition(timeout: 5.0) {
            let rowCount = try? getDBRowCount()
            return (rowCount ?? 0) >= 1
        }
        
        XCTAssertTrue(success, "App should recover from corrupt DB, create a new one, and successfully insert captures")
        XCTAssertTrue(appProcess?.isRunning == true, "App should not crash on corrupt database")
    }
}
