# Personal Historian — macOS API Reference

Code patterns and API reference for implementing agents. Each section corresponds to a component in the implementation plan.

---

## Table of Contents

1. [ScreenCaptureKit — Screenshot Capture](#1-screencapturekit)
2. [Vision — OCR Text Recognition](#2-vision-ocr)
3. [NSWorkspace — App Tracking](#3-nsworkspace)
4. [CGWindowList — Window Enumeration](#4-cgwindowlist)
5. [Image Processing — Resize & Compress](#5-image-processing)
6. [GRDB.swift — Database & FTS5](#6-grdb-database)
7. [File Storage — Screenshot Management](#7-file-storage)
8. [Menu Bar App — NSStatusItem / MenuBarExtra](#8-menu-bar-app)
9. [Permissions — Screen Recording TCC](#9-permissions)
10. [Login Item — SMAppService](#10-login-item)
11. [System Events — Sleep/Wake/Lock](#11-system-events)
12. [Swift Concurrency Patterns](#12-concurrency)

---

## 1. ScreenCaptureKit

**Framework**: `ScreenCaptureKit`
**Minimum**: macOS 12.3 (SCStream), macOS 14.0 (SCScreenshotManager)
**Import**: `import ScreenCaptureKit`

### Capture Full Display

```swift
import ScreenCaptureKit

func captureMainDisplay() async throws -> CGImage {
    // 1. Enumerate shareable content (also triggers permission dialog)
    let content = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
    )

    // 2. Get primary display
    guard let display = content.displays.first else {
        throw ScreenCaptureError.noDisplayFound
    }

    // 3. Configure capture filter (full display, include all apps)
    let filter = SCContentFilter(
        display: display,
        excludingApplications: [],
        exceptingWindows: []
    )

    // 4. Configure resolution (native Retina)
    let config = SCStreamConfiguration()
    config.width = display.width * 2     // Retina: logical × 2
    config.height = display.height * 2
    config.showsCursor = false           // Cleaner for OCR
    config.captureResolution = .best
    config.colorSpaceName = CGColorSpace.sRGB

    // 5. Capture single frame
    let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: config
    )

    return image
}
```

### Gotchas

- **Permission check**: Call `CGPreflightScreenCaptureAccess()` before attempting capture. Without permission, `SCShareableContent` succeeds but returned content only shows the desktop wallpaper.
- **`display.width` is in points**: Multiply by 2 for Retina pixels. On the M4 Pro MacBook Pro 14", `display.width = 1512`, `display.height = 982`, so capture at 3024×1964.
- **Thread safety**: `SCScreenshotManager.captureImage()` is fully async and thread-safe.
- **Memory**: The returned CGImage is ~24 MB (3024×1964×4 bytes RGBA). Release it promptly after processing.

---

## 2. Vision OCR

**Framework**: `Vision`
**Import**: `import Vision`

### Recognize Text in Screenshot

```swift
import Vision

func recognizeText(
    in image: CGImage,
    level: VNRequestTextRecognitionLevel = .accurate
) async throws -> String {
    // Create request
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = true

    // Perform recognition (synchronous but CPU-bound — call off main thread)
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    // Extract text from observations
    guard let observations = request.results else { return "" }

    let lines = observations
        .filter { $0.confidence >= 0.3 }   // Filter noise
        .compactMap { $0.topCandidates(1).first?.string }

    return lines.joined(separator: "\n")
}
```

### Recognition Levels

| Level | Enum Value | Speed (M4 Pro, 1080p) | Use Case |
|-------|-----------|----------------------|----------|
| Fast | `.fast` | ~10–30ms | High-frequency captures, simple text |
| Accurate | `.accurate` | ~100–200ms | Default — better for UI text, small fonts |

### Performance Notes

- **Neural Engine**: Vision uses the Apple Neural Engine when available — zero GPU/CPU contention.
- `handler.perform()` is **synchronous** — it blocks the calling thread. Always call from a `nonisolated` function or `Task.detached` to avoid blocking the main thread.
- **Language correction** (`usesLanguageCorrection = true`) adds ~20% latency but significantly improves accuracy for natural language text.
- **Confidence filtering**: Screen UIs contain decorative elements that produce low-confidence OCR noise. A threshold of 0.3 removes most noise while keeping legitimate text.

### Alternative: Modern Async API (macOS 15+)

```swift
// If targeting macOS 15+, this is simpler:
import Vision

let request = RecognizeTextRequest()
request.recognitionLevel = .accurate
let observations = try await request.perform(on: image)
```

---

## 3. NSWorkspace

**Framework**: `AppKit`
**Import**: `import AppKit`

### Get Frontmost Application

```swift
if let app = NSWorkspace.shared.frontmostApplication {
    let info = RunningAppInfo(
        name: app.localizedName ?? "Unknown",
        bundleIdentifier: app.bundleIdentifier ?? "",
        processIdentifier: app.processIdentifier,
        isForeground: true
    )
}
```

### List User-Facing Applications

```swift
let userApps = NSWorkspace.shared.runningApplications
    .filter { $0.activationPolicy == .regular }  // Dock-visible apps only
    .map { app in
        RunningAppInfo(
            name: app.localizedName ?? "Unknown",
            bundleIdentifier: app.bundleIdentifier ?? "",
            processIdentifier: app.processIdentifier,
            isForeground: app == NSWorkspace.shared.frontmostApplication
        )
    }
```

### Activation Policies

| Policy | Description | Examples |
|--------|-------------|---------|
| `.regular` | Standard apps visible in Dock | Safari, Xcode, Slack |
| `.accessory` | Menu bar apps / background UI | Our app, Bartender, iStat |
| `.prohibited` | Truly background processes | Spotlight, mdworker |

**Use `.regular` to filter** for user-facing apps. This excludes system daemons, background agents, and menu bar utilities.

### Observe Foreground App Changes (Real-Time Tracking)

```swift
// Register for notifications
NSWorkspace.shared.notificationCenter.addObserver(
    self,
    selector: #selector(appDidActivate(_:)),
    name: NSWorkspace.didActivateApplicationNotification,
    object: nil
)

@objc func appDidActivate(_ notification: Notification) {
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication else { return }

    let now = Date()

    // End previous session
    if let currentSession = activeSessions.last, currentSession.endTime == nil {
        currentSession.endTime = now
        currentSession.durationSeconds = now.timeIntervalSince(currentSession.startTime)
        // Save to database
    }

    // Start new session
    let session = AppUsageRecord(
        appName: app.localizedName ?? "Unknown",
        bundleIdentifier: app.bundleIdentifier,
        startTime: now,
        endTime: nil,
        durationSeconds: nil
    )
    // Save to database
}
```

### Gotchas

- `localizedName` can be `nil` for some apps — always provide a fallback.
- `frontmostApplication` returns `nil` if all apps are hidden or the desktop is focused.
- Notifications are delivered on the **main thread** — keep handlers fast.

---

## 4. CGWindowList

**Framework**: `CoreGraphics`
**Import**: `import CoreGraphics`

### Get Window Titles for Running Apps

```swift
func getWindowTitles() -> [Int32: String] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        as? [[String: Any]] else { return [:] }

    var titles: [Int32: String] = [:]

    for window in windowList {
        // Only normal windows (layer 0), not menus/overlays
        guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
        guard let pid = window[kCGWindowOwnerPID as String] as? Int32 else { continue }
        guard let name = window[kCGWindowName as String] as? String, !name.isEmpty else { continue }

        // Keep the first (topmost) window title per PID
        if titles[pid] == nil {
            titles[pid] = name
        }
    }

    return titles
}
```

### Get Title of Foreground App's Window

```swift
func foregroundWindowTitle(pid: Int32) -> String? {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        as? [[String: Any]] else { return nil }

    return windowList
        .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
        .filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
        .compactMap { $0[kCGWindowName as String] as? String }
        .first { !$0.isEmpty }
}
```

### Key Dictionary Keys

| Key Constant | Type | Description |
|-------------|------|-------------|
| `kCGWindowNumber` | Int32 | Unique window ID |
| `kCGWindowOwnerPID` | Int32 | Process ID |
| `kCGWindowOwnerName` | String | Process name |
| `kCGWindowName` | String | Window title (**requires Screen Recording permission**) |
| `kCGWindowLayer` | Int | 0 = normal window |
| `kCGWindowBounds` | Dictionary | Position and size |
| `kCGWindowIsOnscreen` | Int | 1 if visible |

### Gotcha

`kCGWindowName` returns **empty string or nil** for windows of other apps unless Screen Recording permission is granted. Since our app already requires Screen Recording for screenshots, this should work — but verify during testing.

---

## 5. Image Processing

**Frameworks**: `CoreGraphics`, `ImageIO`, `UniformTypeIdentifiers`
**Import**: `import CoreGraphics; import ImageIO; import UniformTypeIdentifiers`

### Resize to Fit 1080p

```swift
func resizeToFit1080p(_ image: CGImage) -> CGImage? {
    let maxWidth: CGFloat = 1920
    let maxHeight: CGFloat = 1080

    let originalWidth = CGFloat(image.width)
    let originalHeight = CGFloat(image.height)

    // Don't upscale
    guard originalWidth > maxWidth || originalHeight > maxHeight else {
        return image
    }

    let scale = min(maxWidth / originalWidth, maxHeight / originalHeight)
    let newWidth = Int(originalWidth * scale)
    let newHeight = Int(originalHeight * scale)

    guard let context = CGContext(
        data: nil,
        width: newWidth,
        height: newHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,  // Auto-calculate
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
    return context.makeImage()
}
```

### Compress to JPEG (using ImageIO — preferred)

```swift
import ImageIO
import UniformTypeIdentifiers

func compressToJPEG(_ image: CGImage, quality: Double) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data as CFMutableData,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    ) else { return nil }

    let options: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: quality
    ]

    CGImageDestinationAddImage(destination, image, options as CFDictionary)

    guard CGImageDestinationFinalize(destination) else { return nil }

    return data as Data
}
```

### Why ImageIO Over NSBitmapImageRep

| Approach | Pros | Cons |
|----------|------|------|
| `CGImageDestination` (ImageIO) | Direct CGImage→JPEG, no intermediate copies, faster | Slightly more verbose API |
| `NSBitmapImageRep` | Simpler API | Requires NSImage→TIFF→BitmapRep conversion — wasteful |

**Use ImageIO** for production code. It's the same engine that powers Preview.app and Photos.

### Quality vs Size (1080p screenshot)

| Quality | Typical Size | Text Readability |
|---------|-------------|-----------------|
| 0.5 | ~80 KB | Good for large text, artifacts on small text |
| 0.7 | ~180 KB | **Recommended** — readable for all text sizes |
| 0.85 | ~350 KB | Excellent |
| 1.0 | ~800 KB | Lossless-equivalent |

---

## 6. GRDB Database

**Package**: [GRDB.swift](https://github.com/groue/GRDB.swift) v6.24+
**Import**: `import GRDB`

### Database Setup

```swift
import GRDB

final class DatabaseManager: Sendable {
    let dbPool: DatabasePool

    init(at path: String) throws {
        // Use DatabasePool for WAL mode (concurrent reads)
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.readonly = false

        dbPool = try DatabasePool(path: path, configuration: config)
        try runMigrations()
    }
}
```

### Migrations

```swift
private func runMigrations() throws {
    var migrator = DatabaseMigrator()

    // Always run in development (wipes DB on schema change)
    #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("v1_create_tables") { db in
        // Snapshots table
        try db.create(table: "snapshots") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("timestamp", .datetime).notNull().unique()
            t.column("foregroundApp", .text).notNull()
            t.column("foregroundBundleId", .text)
            t.column("windowTitle", .text)
            t.column("ocrText", .text)
            t.column("screenshotPath", .text)
            t.column("runningAppsJson", .text)
        }

        // Indexes
        try db.create(
            index: "idx_snapshots_timestamp",
            on: "snapshots",
            columns: ["timestamp"]
        )
        try db.create(
            index: "idx_snapshots_foregroundApp",
            on: "snapshots",
            columns: ["foregroundApp"]
        )

        // FTS5 virtual table (auto-synchronized with snapshots)
        try db.create(virtualTable: "snapshots_fts", using: FTS5()) { t in
            t.synchronize(withTable: "snapshots")
            t.column("foregroundApp")
            t.column("windowTitle")
            t.column("ocrText")
            t.tokenizer = .unicode61()
        }

        // App usage table
        try db.create(table: "app_usage") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("appName", .text).notNull()
            t.column("bundleIdentifier", .text)
            t.column("startTime", .datetime).notNull()
            t.column("endTime", .datetime)
            t.column("durationSeconds", .double)
        }

        try db.create(
            index: "idx_app_usage_startTime",
            on: "app_usage",
            columns: ["startTime"]
        )
        try db.create(
            index: "idx_app_usage_appName",
            on: "app_usage",
            columns: ["appName"]
        )
    }

    try migrator.migrate(dbPool)
}
```

### Record Types

```swift
// GRDB record for snapshots
struct SnapshotRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    var id: Int64?
    var timestamp: Date
    var foregroundApp: String
    var foregroundBundleId: String?
    var windowTitle: String?
    var ocrText: String?
    var screenshotPath: String?
    var runningAppsJson: String?

    static let databaseTableName = "snapshots"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// GRDB record for app usage
struct AppUsageRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    var id: Int64?
    var appName: String
    var bundleIdentifier: String?
    var startTime: Date
    var endTime: Date?
    var durationSeconds: Double?

    static let databaseTableName = "app_usage"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

### FTS5 Search Queries

```swift
// Basic full-text search
func search(query: String, limit: Int = 50) throws -> [SnapshotRecord] {
    try dbPool.read { db in
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else {
            return []
        }

        let sql = """
            SELECT snapshots.*
            FROM snapshots
            JOIN snapshots_fts ON snapshots_fts.rowid = snapshots.id
            WHERE snapshots_fts MATCH ?
            ORDER BY snapshots.timestamp DESC
            LIMIT ?
        """

        return try SnapshotRecord.fetchAll(db, sql: sql, arguments: [pattern, limit])
    }
}

// Search with date range
func search(query: String, from: Date, to: Date, limit: Int = 50) throws -> [SnapshotRecord] {
    try dbPool.read { db in
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else {
            return []
        }

        let sql = """
            SELECT snapshots.*
            FROM snapshots
            JOIN snapshots_fts ON snapshots_fts.rowid = snapshots.id
            WHERE snapshots_fts MATCH ?
              AND snapshots.timestamp BETWEEN ? AND ?
            ORDER BY snapshots.timestamp DESC
            LIMIT ?
        """

        return try SnapshotRecord.fetchAll(
            db, sql: sql,
            arguments: [pattern, from, to, limit]
        )
    }
}
```

### FTS5 Pattern Types

| Pattern Factory | Example Input | Matches |
|----------------|---------------|---------|
| `matchingAllPrefixesIn:` | `"slac mes"` | "Slack", "message" — prefix AND |
| `matchingAllTokensIn:` | `"error warning"` | Rows containing both "error" AND "warning" |
| `matchingAnyTokenIn:` | `"error warning"` | Rows containing "error" OR "warning" |
| `matchingPhrase:` | `"build failed"` | Rows containing "build failed" as adjacent words |

**Recommendation**: Use `matchingAllPrefixesIn:` for the search bar — it provides the best UX for live search (matches as user types).

### Write Operations

```swift
// Insert a new snapshot
func insertSnapshot(_ record: inout SnapshotRecord) throws {
    try dbPool.write { db in
        try record.insert(db)
        // FTS5 is automatically updated via synchronize(withTable:)
    }
}

// End an app usage session
func endAppSession(id: Int64, at endTime: Date) throws {
    try dbPool.write { db in
        if var record = try AppUsageRecord.fetchOne(db, id: id) {
            record.endTime = endTime
            record.durationSeconds = endTime.timeIntervalSince(record.startTime)
            try record.update(db)
        }
    }
}

// Delete old snapshots (retention cleanup)
func deleteSnapshots(olderThan date: Date) throws -> Int {
    try dbPool.write { db in
        try SnapshotRecord
            .filter(Column("timestamp") < date)
            .deleteAll(db)
    }
}
```

---

## 7. File Storage

**Framework**: `Foundation`

### Application Support Directory

```swift
func applicationSupportDirectory() -> URL {
    let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0]
    return appSupport.appendingPathComponent("com.personalhistorian.app")
}

func screenshotsBaseDirectory() -> URL {
    applicationSupportDirectory().appendingPathComponent("screenshots")
}

func databasePath() -> String {
    applicationSupportDirectory()
        .appendingPathComponent("historian.db")
        .path
}
```

### Save Screenshot with Date-Based Path

```swift
func saveScreenshot(_ data: Data, timestamp: Date, appName: String) throws -> String {
    let calendar = Calendar.current
    let year = String(calendar.component(.year, from: timestamp))
    let month = String(format: "%02d", calendar.component(.month, from: timestamp))
    let day = String(format: "%02d", calendar.component(.day, from: timestamp))

    let dateDir = screenshotsBaseDirectory()
        .appendingPathComponent(year)
        .appendingPathComponent(month)
        .appendingPathComponent(day)

    try FileManager.default.createDirectory(
        at: dateDir,
        withIntermediateDirectories: true
    )

    // Filename: HHmmss_AppName.jpg
    let formatter = DateFormatter()
    formatter.dateFormat = "HHmmss"
    let timeStr = formatter.string(from: timestamp)

    let safeName = appName
        .replacingOccurrences(of: "[^a-zA-Z0-9-_]", with: "-", options: .regularExpression)
        .prefix(30)

    let fileName = "\(timeStr)_\(safeName).jpg"
    let filePath = dateDir.appendingPathComponent(fileName)

    try data.write(to: filePath)

    // Return relative path for database storage
    // e.g., "2026/06/08/111547_Safari.jpg"
    return "\(year)/\(month)/\(day)/\(fileName)"
}
```

### Cleanup Old Screenshots

```swift
func cleanupScreenshots(olderThan cutoffDate: Date) throws {
    let baseDir = screenshotsBaseDirectory()
    let fileManager = FileManager.default

    guard let enumerator = fileManager.enumerator(
        at: baseDir,
        includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return }

    var emptyDirs: [URL] = []

    while let fileURL = enumerator.nextObject() as? URL {
        let values = try fileURL.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey])

        if values.isRegularFile == true,
           let created = values.creationDate,
           created < cutoffDate {
            try fileManager.removeItem(at: fileURL)
        }
    }

    // Clean up empty date directories (optional)
    // Walk year/month/day dirs and remove if empty
}
```

### Disk Usage Calculation

```swift
func totalDiskUsage() throws -> UInt64 {
    let baseDir = screenshotsBaseDirectory()
    let fileManager = FileManager.default

    guard let enumerator = fileManager.enumerator(
        at: baseDir,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
    ) else { return 0 }

    var total: UInt64 = 0
    while let fileURL = enumerator.nextObject() as? URL {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        total += UInt64(values.fileSize ?? 0)
    }
    return total
}
```

---

## 8. Menu Bar App

**Framework**: `SwiftUI`

### SwiftUI MenuBarExtra (macOS 13+)

```swift
import SwiftUI

@main
struct PersonalHistorianApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        // Menu bar icon with rich dropdown
        MenuBarExtra("Personal Historian", systemImage: "clock.arrow.circlepath") {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)  // Rich SwiftUI content
        // Use .menu for simple menu items instead

        // Search window (opened programmatically)
        Window("Search History", id: "search") {
            SearchView()
                .environment(appState)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 800, height: 600)

        // Standard Settings window
        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
```

### Hide from Dock

In `Info.plist`:
```xml
<key>LSUIElement</key>
<true/>
```

This makes the app a "UI Element" app — it shows in the menu bar but NOT in the Dock or Cmd+Tab switcher.

### Open Settings Programmatically

```swift
// macOS 14+
if #available(macOS 14.0, *) {
    NSApp.activate()
    // Use SettingsLink() in SwiftUI, or:
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}
```

### Open Named Window Programmatically

```swift
// From within a SwiftUI view:
@Environment(\.openWindow) private var openWindow

Button("Search History...") {
    openWindow(id: "search")
    NSApp.activate(ignoringOtherApps: true)
}
```

---

## 9. Permissions

### Check Screen Recording Permission

```swift
import CoreGraphics

func hasScreenRecordingPermission() -> Bool {
    return CGPreflightScreenCaptureAccess()
}
```

### Request Screen Recording Permission

```swift
func requestScreenRecordingPermission() -> Bool {
    // Shows system dialog on first call.
    // Returns true if already granted, false if user hasn't responded yet.
    return CGRequestScreenCaptureAccess()
}
```

### Open System Settings (fallback)

```swift
import AppKit

func openScreenRecordingSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
        NSWorkspace.shared.open(url)
    }
}
```

### Important Behaviors

1. **After granting**: User must **fully quit** the app (Cmd+Q) and relaunch. TCC permission is only checked at process start.
2. **During development**: Reset permission with:
   ```bash
   tccutil reset ScreenCapture com.personalhistorian.app
   ```
3. **Code signing required**: Unsigned apps lose permission on every rebuild. Always sign with at least `"Apple Development"`.
4. **Detection of denied state**: If `CGPreflightScreenCaptureAccess()` returns false AND we've already asked once, the user denied. Show the System Settings fallback.

---

## 10. Login Item

**Framework**: `ServiceManagement`
**Import**: `import ServiceManagement`

```swift
import ServiceManagement

// Enable launch at login
func enableLaunchAtLogin() throws {
    try SMAppService.mainApp.register()
}

// Disable
func disableLaunchAtLogin() throws {
    try SMAppService.mainApp.unregister()
}

// Check status
func isLaunchAtLoginEnabled() -> Bool {
    SMAppService.mainApp.status == .enabled
}
```

### Status Values

| Status | Meaning |
|--------|---------|
| `.enabled` | Registered and will launch at login |
| `.notRegistered` | Not registered |
| `.requiresApproval` | Registered but pending user approval in System Settings |
| `.notFound` | App not found |

---

## 11. System Events

### Sleep / Wake

```swift
// Observe sleep
NSWorkspace.shared.notificationCenter.addObserver(
    self,
    selector: #selector(systemWillSleep),
    name: NSWorkspace.willSleepNotification,
    object: nil
)

// Observe wake
NSWorkspace.shared.notificationCenter.addObserver(
    self,
    selector: #selector(systemDidWake),
    name: NSWorkspace.didWakeNotification,
    object: nil
)

@objc func systemWillSleep(_ notification: Notification) {
    // Pause capture loop
    // End current app usage session
}

@objc func systemDidWake(_ notification: Notification) {
    // Wait 3 seconds for display to stabilize, then resume
    Task {
        try? await Task.sleep(for: .seconds(3))
        // Resume capture loop
    }
}
```

### Screen Lock / Unlock

```swift
DistributedNotificationCenter.default().addObserver(
    self,
    selector: #selector(screenDidLock),
    name: NSNotification.Name("com.apple.screenIsLocked"),
    object: nil
)

DistributedNotificationCenter.default().addObserver(
    self,
    selector: #selector(screenDidUnlock),
    name: NSNotification.Name("com.apple.screenIsUnlocked"),
    object: nil
)
```

---

## 12. Concurrency

### Pipeline Pattern (Recommended)

```swift
@MainActor
final class CaptureScheduler {
    private var captureTask: Task<Void, Never>?

    func start(intervalSeconds: Int) {
        captureTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let start = CFAbsoluteTimeGetCurrent()
                do {
                    try await self.performCapture()
                } catch {
                    Logger.capture.error("Capture failed: \(error)")
                }
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                let sleep = max(1, Double(intervalSeconds) - elapsed)
                try? await Task.sleep(for: .seconds(sleep))
            }
        }
    }

    func stop() {
        captureTask?.cancel()
        captureTask = nil
    }

    // This is nonisolated — runs on the cooperative thread pool
    nonisolated private func performCapture() async throws {
        // Parallel: screenshot + app info
        async let screenshot = screenCapture.captureMainDisplay()
        let appInfo = await MainActor.run { appTracker.snapshot() }
        let image = try await screenshot

        // Parallel: OCR + resize
        async let ocrResult = ocrEngine.recognizeText(in: image, level: .accurate)
        async let jpegResult = imageProcessor.processForStorage(image, maxHeight: 1080, quality: 0.7)

        let ocrText = try await ocrResult
        guard let jpegData = await jpegResult else {
            throw CaptureError.processingFailed
        }

        // Sequential: save
        let path = try screenshotStorage.save(jpegData, timestamp: Date(), appName: appInfo.foreground.name)
        var record = SnapshotRecord(/* ... */)
        try await databaseManager.insertSnapshot(&record)
    }
}
```

### Key Rules

| Do | Don't |
|----|-------|
| `Task.detached(priority: .utility)` for pipeline | `DispatchQueue.global().async` |
| `@MainActor` for UI state | `DispatchQueue.main.async` |
| `async let` for parallel work | Nested `Task { }` for parallelism |
| `Task.isCancelled` check in loops | `while true` without cancellation |
| `try? await Task.sleep(for:)` | `Thread.sleep()` or `usleep()` |
| `nonisolated func` for CPU work | Doing heavy work in `@MainActor` |
