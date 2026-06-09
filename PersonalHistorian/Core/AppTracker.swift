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
        NotificationCenter.default.addObserver(
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
                foregroundApp = nil
            } else {
                foregroundApp = RunningAppInfo(
                    name: name,
                    bundleIdentifier: bundleId,
                    processIdentifier: front.processIdentifier,
                    isForeground: true
                )
            }
        }
        observeConfiguration()
    }
    
    func stopTracking() {
        isTracking = false
        NotificationCenter.default.removeObserver(self, name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    
    @objc private func didActivateApp(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let name = app.localizedName else {
            foregroundApp = nil
            onAppSwitch?(nil)
            return
        }
        
        let bundleId = app.bundleIdentifier ?? "unknown.\(name)"
        
        // Skip if excluded
        if configuration.excludedBundleIDs.contains(bundleId) {
            foregroundApp = nil
            onAppSwitch?(nil)
            return
        }
        
        foregroundApp = RunningAppInfo(
            name: name,
            bundleIdentifier: bundleId,
            processIdentifier: app.processIdentifier,
            isForeground: true
        )
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
                    self.foregroundApp = nil
                    self.onAppSwitch?(nil)
                } else if self.foregroundApp == nil {
                    if let frontApp = NSWorkspace.shared.frontmostApplication,
                       let name = frontApp.localizedName {
                        let bundleId = frontApp.bundleIdentifier ?? "unknown.\(name)"
                        if !self.configuration.excludedBundleIDs.contains(bundleId) {
                            self.foregroundApp = RunningAppInfo(
                                name: name,
                                bundleIdentifier: bundleId,
                                processIdentifier: frontApp.processIdentifier,
                                isForeground: true
                            )
                            self.onAppSwitch?(self.foregroundApp)
                        }
                    }
                }
            }
        }
    }
}
