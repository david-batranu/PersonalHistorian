import Foundation
import AppKit
import OSLog

@MainActor
final class SystemObserver {
    weak var appState: AppState?
    private let logger = Logger(subsystem: "com.personalhistorian.app", category: "SystemObserver")
    
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
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    @objc private func handleSleep() {
        logger.info("System sleeping. Pausing captures.")
        if let state = appState, state.isRecording {
            Task { await state.captureScheduler.stop() }
        }
    }
    
    @objc private func handleWake() {
        logger.info("System woke up. Resuming captures.")
        if let state = appState, state.isRecording {
            // Give the system a few seconds to stabilize displays
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                Task { await state.captureScheduler.start() }
            }
        }
    }
    
    @objc private func handleScreenLocked() {
        logger.info("Screen locked. Pausing captures.")
        if let state = appState, state.isRecording {
            Task { await state.captureScheduler.stop() }
        }
    }
    
    @objc private func handleScreenUnlocked() {
        logger.info("Screen unlocked. Resuming captures.")
        if let state = appState, state.isRecording {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task { await state.captureScheduler.start() }
            }
        }
    }
}
