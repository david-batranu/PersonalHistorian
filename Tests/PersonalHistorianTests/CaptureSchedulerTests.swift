import XCTest
@testable import PersonalHistorian

@MainActor
final class CaptureSchedulerTests: XCTestCase {
    var appState: AppState!
    
    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
    }
    
    override func tearDown() async throws {
        appState.stopRecording()
        appState = nil
        try await super.tearDown()
    }
    
    func testStartAndStop() async throws {
        // Given
        let scheduler = CaptureScheduler()
        let state = await AppState()
        await scheduler.setAppState(state)
        
        // When
        await scheduler.start()
        
        // Then (wait briefly for task to start and fail because permissions are denied in tests)
        try await Task.sleep(nanoseconds: 100_000_000)
        await scheduler.stop()
        
        let count = await state.captureCount
        XCTAssertEqual(count, 0, "Should not increment capture count without foreground apps or permissions")
    }
}
