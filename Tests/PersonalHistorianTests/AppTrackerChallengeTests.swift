import XCTest
import AppKit
@testable import PersonalHistorian

@MainActor
final class AppTrackerChallengeTests: XCTestCase {
    
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

    func testAppRemovedFromExclusionBecomesForeground() {
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
