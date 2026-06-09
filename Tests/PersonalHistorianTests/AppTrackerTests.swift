import XCTest
import AppKit
@testable import PersonalHistorian

@MainActor
final class AppTrackerTests: XCTestCase {
    
    private var testDefaultsSuiteName: String!
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaultsSuiteName = UUID().uuidString
        testDefaults = UserDefaults(suiteName: testDefaultsSuiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: testDefaultsSuiteName)
        super.tearDown()
    }
    
    func testAppTrackerInitialization() {
        let config = Configuration(defaults: testDefaults)
        let tracker = AppTracker(configuration: config)
        XCTAssertNil(tracker.foregroundApp)
    }
    
    func testExcludedAppSetsForegroundToNilAndFiresOnAppSwitch() throws {
        try XCTSkipIf(NSWorkspace.shared.frontmostApplication == nil, "Test skipped in headless environment")
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else {
            XCTFail("Should have a frontmost app with a bundle ID")
            return
        }
        
        // Exclude the front app's bundle ID
        var config = Configuration(defaults: testDefaults)
        config.excludedBundleIDs = [bundleId]
        
        let tracker = AppTracker(configuration: config)
        
        var switchCount = 0
        // Set to non-nil dummy to ensure it gets overwritten to nil
        var lastSwitchedApp: RunningAppInfo? = RunningAppInfo(name: "Dummy", bundleIdentifier: "dummy", processIdentifier: 0, isForeground: true)
        
        tracker.onAppSwitch = { appInfo in
            switchCount += 1
            lastSwitchedApp = appInfo
        }
        
        tracker.startTracking()
        
        // It's possible startTracking() already fired an onAppSwitch or set foregroundApp if it found frontmostApplication, 
        // but our implementation of startTracking() doesn't fire onAppSwitch right now.
        // It does set foregroundApp to nil because the app is excluded.
        XCTAssertNil(tracker.foregroundApp)
        
        // Simulate activation of the excluded app
        let notification = Notification(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: frontApp]
        )
        
        NotificationCenter.default.post(notification)
        
        XCTAssertNil(tracker.foregroundApp)
        XCTAssertEqual(switchCount, 1)
        XCTAssertNil(lastSwitchedApp)
        
        tracker.stopTracking()
    }
    
    func testNonExcludedAppSetsForegroundAndFiresOnAppSwitch() throws {
        try XCTSkipIf(NSWorkspace.shared.frontmostApplication == nil, "Test skipped in headless environment")
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else {
            XCTFail("Should have a frontmost app with a bundle ID")
            return
        }
        
        var config = Configuration(defaults: testDefaults)
        config.excludedBundleIDs = []
        
        let tracker = AppTracker(configuration: config)
        
        var switchCount = 0
        var lastSwitchedApp: RunningAppInfo? = nil
        
        tracker.onAppSwitch = { appInfo in
            switchCount += 1
            lastSwitchedApp = appInfo
        }
        
        tracker.startTracking()
        
        let notification = Notification(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: frontApp]
        )
        
        NotificationCenter.default.post(notification)
        
        XCTAssertNotNil(tracker.foregroundApp)
        XCTAssertEqual(tracker.foregroundApp?.bundleIdentifier, bundleId)
        
        XCTAssertEqual(switchCount, 1)
        XCTAssertNotNil(lastSwitchedApp)
        XCTAssertEqual(lastSwitchedApp?.bundleIdentifier, bundleId)
        
        tracker.stopTracking()
    }
    
    func testSnapshotWithExcludedApp() throws {
        try XCTSkipIf(NSWorkspace.shared.frontmostApplication == nil, "Test skipped in headless environment")
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else {
            XCTFail("Should have a frontmost app with a bundle ID")
            return
        }
        
        // Exclude the front app's bundle ID
        var config = Configuration(defaults: testDefaults)
        config.excludedBundleIDs = [bundleId]
        
        let tracker = AppTracker(configuration: config)
        let snapshot = tracker.snapshot()
        
        // Even if the current app is frontmost, it's excluded, so foreground should be nil
        XCTAssertNil(snapshot.foreground)
        
        // The current app should also not appear in the running array
        let isCurrentAppRunning = snapshot.running.contains(where: { $0.bundleIdentifier == bundleId })
        XCTAssertFalse(isCurrentAppRunning)
    }

    func testAppRemovedFromExclusionBecomesForeground() throws {
        try XCTSkipIf(NSWorkspace.shared.frontmostApplication == nil, "Test skipped in headless environment")
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else {
            XCTFail("Should have a frontmost app with a bundle ID")
            return
        }
        
        var config = Configuration(defaults: testDefaults)
        config.excludedBundleIDs = [bundleId]
        
        let tracker = AppTracker(configuration: config)
        tracker.startTracking()
        
        XCTAssertNil(tracker.foregroundApp, "App should initially be excluded")
        
        let expectation = XCTestExpectation(description: "App becomes tracked after exclusion removed")
        
        tracker.onAppSwitch = { appInfo in
            if appInfo?.bundleIdentifier == bundleId {
                expectation.fulfill()
            }
        }
        
        // Remove from exclusion
        config.excludedBundleIDs = []
        
        // Let Task { @MainActor run
        let result = XCTWaiter.wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(result, .completed, "Foreground app should update when exclusion is removed")
        XCTAssertNotNil(tracker.foregroundApp)
        XCTAssertEqual(tracker.foregroundApp?.bundleIdentifier, bundleId)
        
        tracker.stopTracking()
    }
}
