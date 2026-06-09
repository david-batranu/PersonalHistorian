import XCTest
import AppKit

public struct E2EConfig {
    public static var currentTestID = UUID().uuidString
    
    static var bundleID: String {
        "com.personalhistorian.app.test.\(currentTestID)"
    }
    
    static var appSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(bundleID)
    }
    
    static var dbURL: URL {
        appSupportURL.appendingPathComponent("historian.db")
    }
    
    static var screenshotsURL: URL {
        appSupportURL.appendingPathComponent("screenshots")
    }
    
    static var appExecutableURL: URL {
        var currentURL = Bundle(for: AppRunner.self).bundleURL
        while currentURL.pathComponents.count > 1 {
            if currentURL.lastPathComponent == "PersonalHistorian.app" {
                return currentURL.appendingPathComponent("Contents/MacOS/PersonalHistorian")
            }
            currentURL = currentURL.deletingLastPathComponent()
        }
        let bundlePath = Bundle(for: AppRunner.self).bundleURL.deletingLastPathComponent()
        let appPath = bundlePath.appendingPathComponent("PersonalHistorian.app/Contents/MacOS/PersonalHistorian")
        if FileManager.default.fileExists(atPath: appPath.path) { return appPath }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/Debug/PersonalHistorian.app/Contents/MacOS/PersonalHistorian")
    }
}

public class AppRunner {
    public var appProcess: Process?
    
    public init() {}
    
    public func launchApp() throws {
        let process = Process()
        process.executableURL = E2EConfig.appExecutableURL
        try process.run()
        appProcess = process
    }
    
    public func terminateApp() {
        if let process = appProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        appProcess = nil
    }
}

public class ConfigurationManager {
    let defaults = UserDefaults(suiteName: "com.personalhistorian.prefs")!
    
    public init() {}
    
    public func setAppConfig(key: String, value: Any?) {
        if let value = value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }
    
    public func resetConfig() {
        defaults.removePersistentDomain(forName: "com.personalhistorian.prefs")
        defaults.synchronize()
    }
}

public class DatabaseValidator {
    public init() {}
    
    public func deleteStorageDirectory() throws {
        if FileManager.default.fileExists(atPath: E2EConfig.appSupportURL.path) {
            try FileManager.default.removeItem(at: E2EConfig.appSupportURL)
        }
    }
    
    public func checkDatabaseExists() -> Bool {
        return FileManager.default.fileExists(atPath: E2EConfig.dbURL.path)
    }
    
    public func checkScreenshotsDirectoryExists() -> Bool {
        return FileManager.default.fileExists(atPath: E2EConfig.screenshotsURL.path)
    }
    
    public func getSnapshotCount() throws -> Int {
        let result = try executeSQLite(query: "SELECT count(*) FROM snapshots;")
        return Int(result) ?? 0
    }
    
    public func executeSQLite(query: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [E2EConfig.dbURL.path, query]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

public func waitForCondition(timeout: TimeInterval = 5.0, pollInterval: TimeInterval = 0.5, condition: () throws -> Bool) rethrows -> Bool {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        if try condition() {
            return true
        }
        Thread.sleep(forTimeInterval: pollInterval)
    }
    return false
}
