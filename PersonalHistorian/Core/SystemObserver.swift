import Foundation
import AppKit
import OSLog

/// Observes system sleep/wake and screen lock/unlock events, pausing and resuming
/// the capture scheduler accordingly.
@MainActor
final class SystemObserver {
    weak var appState: AppState?
    private let logger = Logger(subsystem: "com.personalhistorian.app", category: "SystemObserver")

    /// Tracks a pending delayed-resume task so it can be cancelled if `stop()` is called
    /// before the delay fires (e.g. stop() called during the 3-second wake delay).
    private var pendingResumeTask: Task<Void, Never>?

    init() {}

    func start() {
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter

        notificationCenter.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleScreenLocked), name: NSWorkspace.screensDidSleepNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleScreenUnlocked), name: NSWorkspace.screensDidWakeNotification, object: nil)

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleScreenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleScreenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        logger.info("System observer started")
    }

    func stop() {
        // Cancel any pending delayed resume before removing observers
        pendingResumeTask?.cancel()
        pendingResumeTask = nil

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        logger.info("System observer stopped")
    }

    @objc private func handleSleep() {
        logger.info("System sleeping. Pausing captures.")
        // Cancel any pending resume that hasn't fired yet
        pendingResumeTask?.cancel()
        pendingResumeTask = nil
        if let state = appState, state.isRecording {
            Task { await state.captureScheduler.stop() }
        }
    }

    @objc private func handleWake() {
        logger.info("System woke up. Scheduling capture resume in 3s.")
        guard let state = appState, state.isRecording else { return }
        // Give the system a few seconds to stabilize displays before resuming
        pendingResumeTask = Task {
            do {
                try await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await state.captureScheduler.start()
            } catch {
                // Task was cancelled — no action needed
            }
        }
    }

    @objc private func handleScreenLocked() {
        logger.info("Screen locked. Pausing captures.")
        // Cancel any pending resume that hasn't fired yet
        pendingResumeTask?.cancel()
        pendingResumeTask = nil
        if let state = appState, state.isRecording {
            Task { await state.captureScheduler.stop() }
        }
    }

    @objc private func handleScreenUnlocked() {
        logger.info("Screen unlocked. Scheduling capture resume in 1s.")
        guard let state = appState, state.isRecording else { return }
        pendingResumeTask = Task {
            do {
                try await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await state.captureScheduler.start()
            } catch {
                // Task was cancelled — no action needed
            }
        }
    }
}
