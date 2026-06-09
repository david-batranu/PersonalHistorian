import XCTest
import AppKit

final class E2EOCRTests: XCTestCase {

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
        return URL(fileURLWithPath: "build/Debug/PersonalHistorian.app/Contents/MacOS/PersonalHistorian")
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        E2EConfig.currentTestID = UUID().uuidString
        
        if FileManager.default.fileExists(atPath: appSupportURL.path) {
            try FileManager.default.removeItem(at: appSupportURL)
        }
        
        defaults.removePersistentDomain(forName: bundleID)
        defaults.synchronize()
    }

    override func tearDownWithError() throws {
        terminateApp()
        
        if FileManager.default.fileExists(atPath: appSupportURL.path) {
            try FileManager.default.removeItem(at: appSupportURL)
        }
        
        try super.tearDownWithError()
    }
    
    // MARK: - Helpers
    
    private func launchApp(captureEnabled: Bool = true, interval: Int = 1, ocrEnabled: Bool = true, recognitionLevel: String = "accurate", quality: Double = 1.0) throws {
        defaults.set(captureEnabled, forKey: "isRecording")
        defaults.set(interval, forKey: "captureIntervalSeconds")
        defaults.set(ocrEnabled, forKey: "isOCREnabled")
        defaults.set(recognitionLevel, forKey: "ocrRecognitionLevel")
        defaults.set(quality, forKey: "imageQuality")
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
    
    private func getDBRowCount(table: String = "snapshots") throws -> Int {
        let result = try executeSQLite(query: "SELECT count(*) FROM \(table);")
        return Int(result) ?? 0
    }
    
    private func waitForCondition(timeout: TimeInterval = 6.0, pollInterval: TimeInterval = 0.5, condition: () throws -> Bool) rethrows -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if try condition() {
                return true
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return false
    }

    private func displayTestTextOnScreen(_ text: String, size: CGFloat = 48) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 400),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.level = .floating
        window.backgroundColor = .white
        
        let textField = NSTextField(labelWithString: text)
        textField.font = NSFont.systemFont(ofSize: size)
        textField.textColor = .black
        textField.alignment = .center
        textField.frame = window.contentView!.bounds
        textField.maximumNumberOfLines = 0
        textField.lineBreakMode = .byWordWrapping
        
        window.contentView?.addSubview(textField)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    // MARK: - Tier 1: Feature Coverage
    
    func testOCR_BasicTextExtraction() throws {
        let testString = "E2E_BASIC_EXTRACTION_TEST"
        let window = displayTestTextOnScreen(testString)
        defer { window.close() }
        
        try launchApp()
        
        let success = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            return rowData.contains(testString)
        }
        
        XCTAssertTrue(success, "OCR should extract basic text from the screen")
    }
    
    func testOCR_RecognitionLevelFast() throws {
        let testString = "E2E_FAST_RECOGNITION"
        let window = displayTestTextOnScreen(testString)
        defer { window.close() }
        
        try launchApp(recognitionLevel: "fast")
        
        let success = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            return rowData.contains(testString)
        }
        
        XCTAssertTrue(success, "OCR should work with 'fast' recognition level")
    }
    
    func testOCR_RecognitionLevelAccurate() throws {
        let testString = "E2E_ACCURATE_RECOGNITION"
        let window = displayTestTextOnScreen(testString)
        defer { window.close() }
        
        try launchApp(recognitionLevel: "accurate")
        
        let success = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            return rowData.contains(testString)
        }
        
        XCTAssertTrue(success, "OCR should work with 'accurate' recognition level")
    }
    
    func testOCR_MultilineText() throws {
        let testString = "LINE_ONE_E2E\nLINE_TWO_E2E\nLINE_THREE_E2E"
        let window = displayTestTextOnScreen(testString)
        defer { window.close() }
        
        try launchApp()
        
        let success = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            return rowData.contains("LINE_ONE_E2E") && rowData.contains("LINE_TWO_E2E") && rowData.contains("LINE_THREE_E2E")
        }
        
        XCTAssertTrue(success, "OCR should extract multiple lines of text correctly")
    }
    
    func testOCR_DesktopMenuBarText() throws {
        // App is assumed to be capturing the whole screen, which includes the menu bar.
        // We look for a common menu bar item. "File" or "Edit" or "Apple" is almost always there.
        try launchApp()
        
        let success = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            return rowData.contains("File") || rowData.contains("Edit") || rowData.contains("View")
        }
        
        XCTAssertTrue(success, "OCR should capture default menu bar text")
    }

    // MARK: - Tier 2: Boundary & Corner Cases
    
    func testOCR_VeryLongText() throws {
        let repeatedString = String(repeating: "VERY_LONG_TEXT_CHUNK ", count: 50)
        let window = displayTestTextOnScreen(repeatedString, size: 24)
        defer { window.close() }
        
        try launchApp()
        
        let success = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            // Verify at least a few chunks are captured
            return rowData.components(separatedBy: "VERY_LONG_TEXT_CHUNK").count > 10
        }
        
        XCTAssertTrue(success, "OCR should handle very long text")
    }
    
    func testOCR_SpecialCharacters() throws {
        let testString = "!@#$%^&*()_+{}|:<>?-=[]\\;',./"
        let window = displayTestTextOnScreen(testString)
        defer { window.close() }
        
        try launchApp()
        
        let success = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            // OCR might miss some small punctuation, so check for a significant subset
            return rowData.contains("@#$") || rowData.contains("%^&") || rowData.contains("{}|")
        }
        
        XCTAssertTrue(success, "OCR should be able to recognize special characters")
    }
    
    func testOCR_NonEnglishCharacters() throws {
        let testString = "こんにちは世界 안녕하세요 E2E"
        let window = displayTestTextOnScreen(testString)
        defer { window.close() }
        
        try launchApp()
        
        let success = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            return rowData.contains("こんにちは世界") || rowData.contains("안녕하세요")
        }
        
        XCTAssertTrue(success, "OCR should recognize non-English characters with supported language models")
    }
    
    func testOCR_NumericData() throws {
        let testString = "0123456789 9876543210"
        let window = displayTestTextOnScreen(testString)
        defer { window.close() }
        
        try launchApp()
        
        let success = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            return rowData.contains("0123456789")
        }
        
        XCTAssertTrue(success, "OCR should extract purely numeric data")
    }
    
    func testOCR_TinyFont() throws {
        let testString = "E2E_TINY_FONT_TEST_STRING"
        // Size 8 is small but generally readable by modern OCR in accurate mode
        let window = displayTestTextOnScreen(testString, size: 8)
        defer { window.close() }
        
        try launchApp(recognitionLevel: "accurate")
        
        let success = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            return rowData.contains(testString)
        }
        
        XCTAssertTrue(success, "OCR accurate mode should be able to read tiny fonts")
    }

    // MARK: - Tier 3: Cross-Feature Combinations
    
    func testOCR_WithLowResolutionStorage() throws {
        let testString = "LOW_RES_STORAGE_OCR_TEST"
        let window = displayTestTextOnScreen(testString)
        defer { window.close() }
        
        // Low quality storage
        try launchApp(quality: 0.1)
        
        let success = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            return rowData.contains(testString)
        }
        
        XCTAssertTrue(success, "OCR should extract text even if image is compressed")
    }
    
    func testOCR_FTS5SearchIntegration() throws {
        let testString = "FTS5_UNIQUE_SEARCH_TOKEN"
        let window = displayTestTextOnScreen(testString)
        defer { window.close() }
        
        try launchApp()
        
        // Wait for the text to be captured and inserted
        let captureSuccess = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            return rowData.contains(testString)
        }
        XCTAssertTrue(captureSuccess, "Text must be captured first")
        
        // Query the FTS5 table
        let searchResult = try executeSQLite(query: "SELECT count(*) FROM snapshots_fts WHERE ocrText MATCH 'FTS5_UNIQUE_SEARCH_TOKEN';")
        let count = Int(searchResult) ?? 0
        
        XCTAssertGreaterThan(count, 0, "OCR text should be integrated and searchable via FTS5 index")
    }
    
    func testOCR_AppTrackingAssociation() throws {
        let testString = "APP_TRACKING_ASSOCIATION_TEST"
        let window = displayTestTextOnScreen(testString)
        defer { window.close() }
        
        try launchApp()
        
        let success = try waitForCondition {
            let rowData = try executeSQLite(query: "SELECT ocrText, foregroundApp FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
            let parts = rowData.components(separatedBy: "|")
            if parts.count >= 2 {
                let text = parts[0]
                let app = parts[1]
                // Since our tests run under xctest, the active app might be "xctest" or "Xcode" or similar depending on environment
                return text.contains(testString) && !app.isEmpty
            }
            return false
        }
        
        XCTAssertTrue(success, "OCR text should be associated with the foregroundApp field in the database")
    }
}
