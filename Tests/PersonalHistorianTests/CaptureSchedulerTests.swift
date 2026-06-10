import XCTest
@testable import PersonalHistorian

@MainActor
final class CaptureSchedulerTests: XCTestCase {
    var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
        // Ensure recording is off before each test
        appState.stopRecording()
    }

    override func tearDown() async throws {
        appState.stopRecording()
        appState = nil
        try await super.tearDown()
    }

    // MARK: - Start / Stop

    func testStartAndStop() async throws {
        let scheduler = CaptureScheduler()
        await scheduler.setAppState(appState)

        await scheduler.start()

        // Wait briefly — capture should not increment without Screen Recording permission
        try await Task.sleep(nanoseconds: 100_000_000)
        await scheduler.stop()

        let count = await appState.captureCount
        XCTAssertEqual(count, 0, "Should not increment capture count without Screen Recording permission")
    }

    func testStartIsIdempotent() async throws {
        let scheduler = CaptureScheduler()
        await scheduler.setAppState(appState)

        // Calling start() multiple times should not create multiple parallel loops
        await scheduler.start()
        await scheduler.start()
        await scheduler.start()

        try await Task.sleep(nanoseconds: 100_000_000)
        await scheduler.stop()

        // Just verify it doesn't crash and stops cleanly
        let count = await appState.captureCount
        XCTAssertEqual(count, 0)
    }

    func testStopBeforeStartDoesNotCrash() async {
        let scheduler = CaptureScheduler()
        await scheduler.setAppState(appState)

        // stop() before start() should be a no-op
        await scheduler.stop()
        // No assertion needed — just verify no crash
    }

    func testStopDuringActiveTask() async throws {
        let scheduler = CaptureScheduler()
        await scheduler.setAppState(appState)

        await scheduler.start()
        // Stop almost immediately — tests that task cancellation is clean
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await scheduler.stop()

        // After stop, a brief wait should show no further captures
        let countAfterStop = await appState.captureCount
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        let countAfterWait = await appState.captureCount
        XCTAssertEqual(countAfterStop, countAfterWait, "No captures should occur after stop()")
    }

    // MARK: - Error Isolation

    func testCaptureNowDoesNotThrowWithoutPermission() async {
        let scheduler = CaptureScheduler()
        await scheduler.setAppState(appState)

        // captureNow() should handle permission denied gracefully (no throw)
        await scheduler.captureNow()
        // If we reach here without crashing, the test passes
    }

    // MARK: - State Management

    func testStartThenStopThenStartAgain() async throws {
        let scheduler = CaptureScheduler()
        await scheduler.setAppState(appState)

        await scheduler.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        await scheduler.stop()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Should be able to restart cleanly
        await scheduler.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        await scheduler.stop()

        let count = await appState.captureCount
        XCTAssertEqual(count, 0, "No captures expected without permission")
    }

    func testAppStateNilDoesNotCrash() async throws {
        let scheduler = CaptureScheduler()
        // Do NOT set appState — scheduler.appState is nil

        await scheduler.start()
        try await Task.sleep(nanoseconds: 100_000_000)
        await scheduler.stop()
        // Should handle nil appState gracefully (logs warning, no crash)
    }
}
