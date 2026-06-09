import XCTest
import AppKit

final class E2EAppTrackingTests: XCTestCase {
    
    var appProcess: Process?
    let prefsSuite = "com.personalhistorian.prefs"
    
    var appSupportURL: URL { return E2EConfig.appSupportURL }
    var dbURL: URL { return E2EConfig.dbURL }
    var screenshotsURL: URL { return E2EConfig.screenshotsURL }
    
    var defaults: UserDefaults {
        UserDefaults(suiteName: prefsSuite) ?? .standard
    }
    
    var appExecutableURL: URL {
        return E2EConfig.appExecutableURL
    }
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        E2EConfig.currentTestID = UUID().uuidString
        
        if FileManager.default.fileExists(atPath: appSupportURL.path) {
            try FileManager.default.removeItem(at: appSupportURL)
        }
        
        defaults.removePersistentDomain(forName: prefsSuite)
    }
    
    override func tearDownWithError() throws {
        terminateApp()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["-9", "PersonalHistorian"]
        try? task.run()
        task.waitUntilExit()
        try super.tearDownWithError()
    }
    
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
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
        appProcess = nil
        
        // Ensure all instances are dead
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier == "com.personalhistorian.app" || app.localizedName == "PersonalHistorian" {
                app.forceTerminate()
            }
            if let bundleID = app.bundleIdentifier, bundleID.starts(with: "com.test.") {
                app.forceTerminate()
            }
        }
        // Wait a moment for termination
        Thread.sleep(forTimeInterval: 0.5)
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
    
    private func getLatestActiveApp() throws -> String {
        return try executeSQLite(query: "SELECT foregroundApp FROM snapshots ORDER BY timestamp DESC LIMIT 1;")
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

    // Helper to run a script to create and launch a dummy app
    private func launchDummyApp(name: String, duration: Int = 30) throws -> NSRunningApplication? {
        let tempDir = FileManager.default.temporaryDirectory
        let appURL = tempDir.appendingPathComponent("\(name).app")
        
        if !FileManager.default.fileExists(atPath: appURL.path) {
            let script = "delay \(duration)"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
            task.arguments = ["-e", script, "-o", appURL.path]
            try task.run()
            task.waitUntilExit()
            
            let plistTask = Process()
            plistTask.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            plistTask.arguments = ["write", appURL.appendingPathComponent("Contents/Info.plist").path, "CFBundleIdentifier", "com.test.\(name)"]
            try plistTask.run()
            plistTask.waitUntilExit()
        }
        
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        
        let sema = DispatchSemaphore(value: 0)
        var launchedApp: NSRunningApplication?
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
            if let error = error {
                print("Error launching dummy app: \(error)")
            }
            launchedApp = app
            app?.activate(options: .activateIgnoringOtherApps)
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 5.0)
        launchedApp?.activate(options: .activateIgnoringOtherApps)
        return launchedApp
    }

    // MARK: - Tier 1: Core Functionality

    func testSingleAppForeground() throws {
        try launchApp(captureEnabled: true, interval: 1)
        
        let dummyApp = try launchDummyApp(name: "TestAppForeground")
        defer { dummyApp?.terminate() }
        
        let success = try waitForCondition(timeout: 15.0) {
            let activeApp = try getLatestActiveApp()
            return activeApp.contains("TestAppForeground")
        }
        XCTAssertTrue(success, "Should capture the single foreground application")
    }

    func testMultipleBackgroundApps() throws {
        let bgApp1 = try launchDummyApp(name: "TestBgApp1")
        let bgApp2 = try launchDummyApp(name: "TestBgApp2")
        defer { 
            bgApp1?.terminate()
            bgApp2?.terminate()
        }
        
        let fgApp = try launchDummyApp(name: "TestFgApp")
        defer { fgApp?.terminate() }
        
        try launchApp(captureEnabled: true, interval: 1)
        
        let success = try waitForCondition(timeout: 15.0) {
            let activeApp = try getLatestActiveApp()
            return activeApp.contains("TestFgApp")
        }
        XCTAssertTrue(success, "Should record the correct foreground app even with multiple background apps")
    }

    func testAppSwitching() throws {
        try launchApp(captureEnabled: true, interval: 1)
        
        let app1 = try launchDummyApp(name: "AppSwitch1")
        defer { app1?.forceTerminate() }
        
        var success = try waitForCondition(timeout: 15.0) {
            try getLatestActiveApp().contains("AppSwitch1")
        }
        XCTAssertTrue(success)
        
        let app2 = try launchDummyApp(name: "AppSwitch2")
        defer { app2?.forceTerminate() }
        
        success = try waitForCondition(timeout: 15.0) {
            try getLatestActiveApp().contains("AppSwitch2")
        }
        XCTAssertTrue(success, "Should update the active app to the newly switched app")
    }

    func testAppTermination() throws {
        try launchApp(captureEnabled: true, interval: 1)
        
        let app = try launchDummyApp(name: "TermApp")
        
        var success = try waitForCondition(timeout: 15.0) {
            try getLatestActiveApp().contains("TermApp")
        }
        XCTAssertTrue(success)
        
        app?.forceTerminate()
        
        success = try waitForCondition(timeout: 15.0) {
            let activeApp = try getLatestActiveApp()
            return !activeApp.contains("TermApp")
        }
        XCTAssertTrue(success, "Terminated app should not be recorded as active")
    }

    func testExcludedApp() throws {
        // App Tracking: Excluded App
        defaults.set(["unknown.ExcludedApp"], forKey: "excludedBundleIDs")
        defaults.synchronize()
        
        try launchApp(captureEnabled: true, interval: 1)
        
        let excluded = try launchDummyApp(name: "ExcludedApp")
        defer { excluded?.terminate() }
        
        Thread.sleep(forTimeInterval: 3.0)
        let activeApp = try getLatestActiveApp()
        XCTAssertFalse(activeApp.contains("ExcludedApp"), "Excluded app should not be tracked")
        
        let countString = try executeSQLite(query: "SELECT count(*) FROM snapshots WHERE appBundleId = 'unknown.ExcludedApp';")
        let count = Int(countString) ?? -1
        XCTAssertEqual(count, 0, "Should skip capture when foreground app is excluded")
    }

    // MARK: - Tier 2: Edge Cases & Boundaries

    func testZeroUserApps() throws {
        NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" })?.activate(options: .activateIgnoringOtherApps)
        
        try launchApp(captureEnabled: true, interval: 1)
        
        let success = try waitForCondition(timeout: 15.0) {
            try { let app = try getLatestActiveApp(); return app.contains("Finder") || app.contains("com.apple.finder") }()
        }
        XCTAssertTrue(success, "Should accurately track system default apps like Finder")
    }

    func testHighVolumeAppsStress() throws {
        var apps: [NSRunningApplication?] = []
        for i in 1...10 {
            apps.append(try launchDummyApp(name: "StressApp\(i)", duration: 20))
        }
        defer { apps.forEach { $0?.terminate() } }
        
        try launchApp(captureEnabled: true, interval: 1)
        
        let success = try waitForCondition(timeout: 15.0) {
            try getLatestActiveApp().contains("StressApp10")
        }
        XCTAssertTrue(success, "Should handle many running applications and identify foreground app correctly")
    }

    func testRapidAppSwitching() throws {
        try launchApp(captureEnabled: true, interval: 2)
        
        let app1 = try launchDummyApp(name: "Rapid1", duration: 20)
        let app2 = try launchDummyApp(name: "Rapid2", duration: 20)
        defer {
            app1?.terminate()
            app2?.terminate()
        }
        
        for _ in 0..<3 {
            app1?.activate(options: .activateIgnoringOtherApps)
            Thread.sleep(forTimeInterval: 0.2)
            app2?.activate(options: .activateIgnoringOtherApps)
            Thread.sleep(forTimeInterval: 0.2)
        }
        app1?.activate(options: .activateIgnoringOtherApps)
        
        let success = try waitForCondition(timeout: 15.0) {
            try getLatestActiveApp().contains("Rapid1")
        }
        XCTAssertTrue(success, "Tracking should capture the app that settled as active after rapid switching")
    }

    func testUnicodeAppName() throws {
        try launchApp(captureEnabled: true, interval: 1)
        
        let appName = "My🦄App"
        let unicodeApp = try launchDummyApp(name: appName)
        defer { unicodeApp?.terminate() }
        
        let success = try waitForCondition(timeout: 15.0) {
            try getLatestActiveApp().contains("My🦄App")
        }
        XCTAssertTrue(success, "App with Unicode characters in name should be recorded correctly")
    }

    func testShortLivedApp() throws {
        try launchApp(captureEnabled: true, interval: 3)
        
        let shortApp = try launchDummyApp(name: "ShortLived", duration: 1)
        Thread.sleep(forTimeInterval: 1.0)
        shortApp?.terminate()
        
        Thread.sleep(forTimeInterval: 3.0)
        
        let data = try executeSQLite(query: "SELECT foregroundApp FROM snapshots;")
        XCTAssertFalse(data.contains("ShortLived"), "Short-lived app closed before capture interval should not be recorded")
    }

    // MARK: - Tier 3: Interactions

    func testHighFrequencyTracking() throws {
        try launchApp(captureEnabled: true, interval: 1)
        
        let hfApp = try launchDummyApp(name: "HighFreq")
        defer { hfApp?.terminate() }
        
        Thread.sleep(forTimeInterval: 4.5)
        
        let count = try getDBRowCount()
        XCTAssertGreaterThanOrEqual(count, 4, "High frequency tracking should produce expected capture count")
        
        let success = try waitForCondition(timeout: 15.0) {
            let activeApp = try getLatestActiveApp()
            return activeApp.contains("HighFreq")
        }
        XCTAssertTrue(success, "Active app should be consistent across rapid captures")
    }

    func testBackgroundExcludedApp() throws {
        defaults.set(["unknown.BgExcluded"], forKey: "excludedBundleIDs")
        defaults.synchronize()
        
        let excluded = try launchDummyApp(name: "BgExcluded", duration: 20)
        defer { excluded?.terminate() }
        
        let fgApp = try launchDummyApp(name: "NormalFgApp", duration: 20)
        defer { fgApp?.terminate() }
        
        try launchApp(captureEnabled: true, interval: 1)
        
        let success = try waitForCondition(timeout: 15.0) {
            let app = try getLatestActiveApp()
            return app.contains("NormalFgApp")
        }
        XCTAssertTrue(success, "An excluded app in the background should not block tracking of a normal foreground app")
    }
}
