import AppKit
import Observation
import OSLog

@MainActor
@Observable
final class AppTracker {
    private(set) var foregroundApp: RunningAppInfo?
    var onAppSwitch: ((RunningAppInfo?) -> Void)?
    private let configuration: Configuration
    private let logger = Logger(subsystem: "com.personalhistorian.app", category: "AppTracker")
    private var isTracking = false
    private var currentSessionStartTime: Date?
    
    weak var appState: AppState?
    
    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    func snapshot() -> (foreground: RunningAppInfo?, running: [RunningAppInfo]) {
        let ws = NSWorkspace.shared
        let runningApps = ws.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningAppInfo? in
                guard let name = app.localizedName else { return nil }
                let bundleId = app.bundleIdentifier ?? "unknown.\(name)"
                if configuration.excludedBundleIDs.contains(bundleId) { return nil }
                
                return RunningAppInfo(
                    name: name,
                    bundleIdentifier: bundleId,
                    processIdentifier: app.processIdentifier,
                    isForeground: app.isActive
                )
            }
        
        var fgApp: RunningAppInfo? = nil
        if let frontApp = ws.frontmostApplication,
           let name = frontApp.localizedName {
            let bundleId = frontApp.bundleIdentifier ?? "unknown.\(name)"
            if !configuration.excludedBundleIDs.contains(bundleId) {
                fgApp = RunningAppInfo(
                    name: name,
                    bundleIdentifier: bundleId,
                    processIdentifier: frontApp.processIdentifier,
                    isForeground: true
                )
            }
        }
        
        return (foreground: fgApp, running: runningApps)
    }
    
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didActivateApp(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        // Set initial foreground app
        if let front = NSWorkspace.shared.frontmostApplication,
           let name = front.localizedName {
            let bundleId = front.bundleIdentifier ?? "unknown.\(name)"
            if configuration.excludedBundleIDs.contains(bundleId) {
                switchForegroundApp(to: nil)
            } else {
                switchForegroundApp(to: RunningAppInfo(
                    name: name,
                    bundleIdentifier: bundleId,
                    processIdentifier: front.processIdentifier,
                    isForeground: true
                ))
            }
        }
        observeConfiguration()
    }
    
    func stopTracking() {
        isTracking = false
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    
    @objc private func didActivateApp(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let name = app.localizedName else {
            switchForegroundApp(to: nil)
            return
        }
        
        let bundleId = app.bundleIdentifier ?? "unknown.\(name)"
        
        // Skip if excluded
        if configuration.excludedBundleIDs.contains(bundleId) {
            switchForegroundApp(to: nil)
            return
        }
        
        switchForegroundApp(to: RunningAppInfo(
            name: name,
            bundleIdentifier: bundleId,
            processIdentifier: app.processIdentifier,
            isForeground: true
        ))
    }
    
    private func switchForegroundApp(to newApp: RunningAppInfo?) {
        let now = Date()
        
        // Close current session
        if let currentApp = foregroundApp, let startTime = currentSessionStartTime {
            if now.timeIntervalSince(startTime) > 1 { // Only record if > 1s
                try? appState?.databaseManager.insertSession(
                    bundleId: currentApp.bundleIdentifier,
                    appName: currentApp.name,
                    startTime: startTime,
                    endTime: now
                )
            }
        }
        
        foregroundApp = newApp
        if newApp != nil {
            currentSessionStartTime = now
        } else {
            currentSessionStartTime = nil
        }
        
        onAppSwitch?(foregroundApp)
    }
    
    private func observeConfiguration() {
        withObservationTracking {
            _ = configuration.excludedBundleIDs
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isTracking else { return }
                self.observeConfiguration()
                if let currentApp = self.foregroundApp, self.configuration.excludedBundleIDs.contains(currentApp.bundleIdentifier) {
                    self.switchForegroundApp(to: nil)
                } else if self.foregroundApp == nil {
                    if let frontApp = NSWorkspace.shared.frontmostApplication,
                       let name = frontApp.localizedName {
                        let bundleId = frontApp.bundleIdentifier ?? "unknown.\(name)"
                        if !self.configuration.excludedBundleIDs.contains(bundleId) {
                            self.switchForegroundApp(to: RunningAppInfo(
                                name: name,
                                bundleIdentifier: bundleId,
                                processIdentifier: frontApp.processIdentifier,
                                isForeground: true
                            ))
                        }
                    }
                }
            }
        }
    }
}
