import XCTest
import AppKit
@testable import PersonalHistorian

/// Additional AppTracker tests focused on performance and edge cases
/// that complement the functional tests in AppTrackerTests.swift.
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

    // MARK: - Performance

    func testSnapshotPerformance() throws {
        try XCTSkipIf(NSWorkspace.shared.frontmostApplication == nil, "Skipped in headless environment")
        let config = Configuration(defaults: testDefaults)
        let tracker = AppTracker(configuration: config)

        // snapshot() should be sub-millisecond — it reads cached NSWorkspace state
        measure {
            _ = tracker.snapshot()
        }
    }

    // MARK: - Edge Cases

    func testSnapshotWithNoRunningApps() {
        // Exclude all running apps to verify snapshot handles an empty list gracefully
        let config = Configuration(defaults: testDefaults)
        let allBundleIds = NSWorkspace.shared.runningApplications
            .compactMap { $0.bundleIdentifier }
        config.excludedBundleIDs = allBundleIds

        let tracker = AppTracker(configuration: config)
        let snapshot = tracker.snapshot()

        // When all apps are excluded, foreground should be nil
        XCTAssertNil(snapshot.foreground, "Foreground should be nil when all apps are excluded")
        // Running list should also be empty
        XCTAssertTrue(snapshot.running.isEmpty, "Running list should be empty when all apps are excluded")
    }

    func testStartAndStopTrackingIsIdempotent() {
        let config = Configuration(defaults: testDefaults)
        let tracker = AppTracker(configuration: config)

        // Multiple start calls should not crash or duplicate observers
        tracker.startTracking()
        tracker.startTracking()
        tracker.startTracking()

        tracker.stopTracking()

        // After stop, another stop should not crash
        tracker.stopTracking()
    }

    func testSnapshotRunningAppsHaveNonEmptyBundleIds() throws {
        try XCTSkipIf(NSWorkspace.shared.frontmostApplication == nil, "Skipped in headless environment")
        let config = Configuration(defaults: testDefaults)
        let tracker = AppTracker(configuration: config)

        let snapshot = tracker.snapshot()
        for app in snapshot.running {
            XCTAssertFalse(app.bundleIdentifier.isEmpty, "Bundle ID should not be empty for \(app.name)")
        }
    }
}
