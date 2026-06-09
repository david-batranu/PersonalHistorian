# Personal Historian — Implementation Plan

A macOS menu bar application that silently records periodic screenshots, extracts visible text via OCR, and tracks active applications — providing a searchable, passive history of everything the user does on their Mac.

## Target Environment

| Property | Value |
|----------|-------|
| Platform | macOS 14.0+ (Sonoma) |
| Language | Swift 5.9+ with strict concurrency |
| UI Framework | SwiftUI (MenuBarExtra) |
| Architecture | Single-process menu bar agent app |
| Hardware Target | Apple Silicon (M4 Pro MacBook) |
| Distribution | Direct (not App Store) — developer-signed |

## Technology Stack

| Concern | Technology | Rationale |
|---------|-----------|-----------|
| Screenshots | **ScreenCaptureKit** (`SCScreenshotManager`) | Modern async API, hardware-accelerated, Apple-recommended replacement for deprecated CG APIs |
| OCR | **Vision** (`VNRecognizeTextRequest`) | On-device Neural Engine acceleration, excellent accuracy on Apple Silicon |
| Active App Tracking | **NSWorkspace** notifications + `CGWindowListCopyWindowInfo` | Real-time foreground tracking via notifications; window list for snapshot-time enumeration |
| Database | **GRDB.swift 6.x** with SQLite FTS5 | Type-safe Swift records, built-in FTS5 support with `synchronize(withTable:)`, WAL mode for concurrent reads |
| Image Processing | **Core Graphics** (`CGContext`) | Simple, sufficient for periodic single-image resize to 1080p |
| Image Format | **JPEG** (quality 0.7) | Universal compatibility for future dashboards; ~150–250 KB per 1080p screenshot |
| Auto-start | **SMAppService** (macOS 13+) | Modern login item API, works with or without sandbox |
| Project Generation | **XcodeGen** | Agent-friendly YAML → .xcodeproj generation; avoids hand-editing pbxproj |

## Project Structure

```
personal_historian/
├── IMPLEMENTATION_PLAN.md              ← you are here
├── ARCHITECTURE.md                     ← system design & data flow
├── API_REFERENCE.md                    ← macOS API patterns & code snippets
│
├── project.yml                         ← XcodeGen project specification
├── Makefile                            ← build, run, clean, generate-project
│
├── PersonalHistorian/
│   ├── Info.plist
│   ├── PersonalHistorian.entitlements
│   │
│   ├── App/
│   │   ├── PersonalHistorianApp.swift  ← @main, MenuBarExtra scene
│   │   └── AppState.swift             ← ObservableObject, owns all services
│   │
│   ├── Core/
│   │   ├── CaptureScheduler.swift     ← Timer loop, pipeline orchestration
│   │   ├── ScreenCapture.swift        ← ScreenCaptureKit wrapper
│   │   ├── OCREngine.swift            ← Vision framework OCR
│   │   ├── AppTracker.swift           ← NSWorkspace foreground tracking
│   │   └── ImageProcessor.swift       ← Resize to 1080p + JPEG compress
│   │
│   ├── Storage/
│   │   ├── DatabaseManager.swift      ← GRDB pool, migrations, accessors
│   │   ├── SnapshotRecord.swift       ← Snapshot table model + FTS5
│   │   ├── AppUsageRecord.swift       ← Application usage table model
│   │   ├── ScreenshotStorage.swift    ← File system management (save/delete/cleanup)
│   │   └── SearchService.swift        ← FTS5 full-text search interface
│   │
│   ├── Models/
│   │   ├── RunningAppInfo.swift       ← Value type for app metadata
│   │   └── CaptureResult.swift        ← Value type for pipeline output
│   │
│   ├── Settings/
│   │   └── Configuration.swift        ← UserDefaults-backed settings
│   │
│   └── Views/
│       ├── MenuBarView.swift          ← Menu bar dropdown content
│       ├── SearchView.swift           ← Search history window (full window)
│       ├── SettingsView.swift         ← Preferences window
│       └── PermissionGuideView.swift  ← Screen recording permission onboarding
│
└── Tests/
    └── PersonalHistorianTests/
        ├── OCREngineTests.swift
        ├── ImageProcessorTests.swift
        ├── DatabaseManagerTests.swift
        ├── SearchServiceTests.swift
        └── CaptureSchedulerTests.swift
```

---

## Phase 1: Project Scaffolding

**Goal**: Buildable, runnable (empty) menu bar app with dependencies resolved.

### 1.1 — `project.yml` (XcodeGen specification)

```yaml
name: PersonalHistorian
options:
  bundleIdPrefix: com.personalhistorian
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true

packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift.git
    from: "6.24.0"

targets:
  PersonalHistorian:
    type: application
    platform: macOS
    sources:
      - PersonalHistorian
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.personalhistorian.app
        INFOPLIST_FILE: PersonalHistorian/Info.plist
        CODE_SIGN_ENTITLEMENTS: PersonalHistorian/PersonalHistorian.entitlements
        CODE_SIGN_IDENTITY: "Apple Development"
        SWIFT_STRICT_CONCURRENCY: complete
        MACOSX_DEPLOYMENT_TARGET: "14.0"
    dependencies:
      - package: GRDB
    entitlements:
      path: PersonalHistorian/PersonalHistorian.entitlements

  PersonalHistorianTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/PersonalHistorianTests
    dependencies:
      - target: PersonalHistorian
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.personalhistorian.tests
```

### 1.2 — `PersonalHistorian/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Hide from Dock — menu bar only -->
    <key>LSUIElement</key>
    <true/>

    <key>CFBundleName</key>
    <string>Personal Historian</string>
    <key>CFBundleDisplayName</key>
    <string>Personal Historian</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>

    <!-- Screen Recording usage description (shown in System Settings) -->
    <key>NSScreenCaptureUsageDescription</key>
    <string>Personal Historian captures periodic screenshots to build a searchable history of your activity.</string>
</dict>
</plist>
```

### 1.3 — `PersonalHistorian/PersonalHistorian.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Non-sandboxed for screen capture access -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

> **Note**: Screen Recording permission is handled by TCC (macOS system dialog), not by entitlements. The app must be **code-signed** for TCC to remember the permission grant. No sandbox is used because ScreenCaptureKit requires it for this use case.

### 1.4 — `PersonalHistorianApp.swift` (minimal stub)

Create a minimal `@main` app with an empty `MenuBarExtra` that proves the app launches, shows an icon in the menu bar, and has a "Quit" button. This validates the project setup.

### 1.5 — `Makefile`

```makefile
.PHONY: generate build run clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project PersonalHistorian.xcodeproj \
		-scheme PersonalHistorian \
		-configuration Debug \
		build

run: build
	open build/Debug/PersonalHistorian.app

clean:
	xcodebuild clean -project PersonalHistorian.xcodeproj -scheme PersonalHistorian
	rm -rf build
```

### Phase 1 — Verification

- [ ] `make generate` produces `PersonalHistorian.xcodeproj` without errors
- [ ] `make build` compiles successfully
- [ ] App launches as a menu bar icon (no Dock icon)
- [ ] "Quit" menu item terminates the app

---

## Phase 2: Configuration & Models

**Goal**: Define all value types, configuration, and the app-wide state container.

### 2.1 — `Configuration.swift`

A `@Observable` class backed by `UserDefaults` with the following settings:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `captureIntervalSeconds` | `Int` | `60` | Time between captures |
| `ocrRecognitionLevel` | `String` | `"accurate"` | `"fast"` or `"accurate"` — maps to `VNRequestTextRecognitionLevel` |
| `imageQuality` | `Double` | `0.7` | JPEG compression quality (0.0–1.0) |
| `maxResolutionHeight` | `Int` | `1080` | Max height for stored screenshots |
| `retentionDays` | `Int` | `30` | Auto-delete screenshots older than this (0 = keep forever) |
| `excludedBundleIDs` | `[String]` | `[]` | Apps to exclude from tracking |
| `isRecording` | `Bool` | `true` | Whether capture is active |
| `launchAtLogin` | `Bool` | `false` | Auto-start on login |

Use `@AppStorage` or direct `UserDefaults.standard` access with a `"com.personalhistorian."` key prefix. Provide a `suite` name for grouped defaults.

### 2.2 — `RunningAppInfo.swift`

```swift
struct RunningAppInfo: Codable, Hashable, Sendable {
    let name: String            // Localized display name
    let bundleIdentifier: String
    let processIdentifier: Int32
    let isForeground: Bool
}
```

Must be `Codable` so the list of running apps can be serialized to JSON in the database.

### 2.3 — `CaptureResult.swift`

```swift
struct CaptureResult: Sendable {
    let timestamp: Date
    let screenshot: CGImage          // Full-resolution capture
    let foregroundApp: RunningAppInfo
    let runningApps: [RunningAppInfo]
    let ocrText: String
}
```

This is the output of the capture pipeline before storage. It is consumed by the storage layer to persist the snapshot and screenshot file.

### 2.4 — `AppState.swift`

An `@Observable @MainActor` class that owns all services and coordinates their lifecycle:

```swift
@Observable @MainActor
final class AppState {
    let configuration: Configuration
    let databaseManager: DatabaseManager
    let screenshotStorage: ScreenshotStorage
    let searchService: SearchService
    let captureScheduler: CaptureScheduler
    let appTracker: AppTracker

    var isRecording: Bool { ... }
    var permissionStatus: PermissionStatus { ... }

    func startRecording() { ... }
    func stopRecording() { ... }
    func checkPermissions() -> PermissionStatus { ... }
}
```

Created in `PersonalHistorianApp.swift` and injected into views via `@Environment`.

### Phase 2 — Verification

- [ ] All model types compile
- [ ] Configuration reads/writes to UserDefaults correctly
- [ ] AppState initializes all services (stubs OK at this point)

---

## Phase 3: Capture Pipeline

**Goal**: Implement the four core engines that gather data each capture cycle.

### Dependency Order

```
ScreenCapture ──┐
OCREngine ──────┤
AppTracker ─────┤──→ CaptureScheduler (Phase 5)
ImageProcessor ─┘
```

Each engine is independent and testable in isolation.

### 3.1 — `ScreenCapture.swift`

**Responsibility**: Capture a screenshot of the entire primary display using ScreenCaptureKit.

```swift
final class ScreenCapture: Sendable {
    /// Captures the primary display at native resolution.
    /// Returns the raw CGImage (full Retina resolution).
    func captureMainDisplay() async throws -> CGImage
    
    /// Checks whether Screen Recording permission has been granted.
    func hasPermission() -> Bool
    
    /// Requests Screen Recording permission (shows system dialog on first call).
    func requestPermission() -> Bool
}
```

**Implementation Details**:

1. Use `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` to enumerate shareable content (this also triggers the permission dialog on first use).
2. Get the first display from `content.displays`.
3. Create an `SCContentFilter` for that display, excluding no applications.
4. Configure `SCStreamConfiguration`:
   - `width` = display width × backing scale factor (Retina)
   - `height` = display height × backing scale factor
   - `showsCursor = false` (less noise in OCR)
   - `captureResolution = .best`
5. Call `SCScreenshotManager.captureImage(contentFilter:configuration:)`.
6. Return the `CGImage`.

**Permission Handling**:
- Use `CGPreflightScreenCaptureAccess()` to check without prompting.
- Use `CGRequestScreenCaptureAccess()` to trigger the system dialog.
- If denied, open System Settings: `"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"`.

**Error Handling**:
- Define `ScreenCaptureError` enum: `.permissionDenied`, `.noDisplayFound`, `.captureFailed(Error)`.

### 3.2 — `OCREngine.swift`

**Responsibility**: Extract all visible text from a screenshot image.

```swift
final class OCREngine: Sendable {
    /// Performs OCR on the given image and returns all recognized text.
    /// Lines are joined with newline characters.
    func recognizeText(in image: CGImage, level: VNRequestTextRecognitionLevel) async throws -> String
}
```

**Implementation Details**:

1. Create a `VNRecognizeTextRequest`.
2. Set `recognitionLevel` based on configuration (`.accurate` by default).
3. Set `recognitionLanguages = ["en-US"]` (expand later if needed).
4. Set `usesLanguageCorrection = true`.
5. Create a `VNImageRequestHandler(cgImage:options:)`.
6. Call `handler.perform([request])` — this is synchronous but should be called from a `nonisolated` context (off main thread).
7. Collect results: `request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")`.
8. Filter observations by minimum `confidence` threshold (0.3) to discard noise.

**Performance Note**: The `perform()` call is CPU/Neural-Engine intensive. It MUST run on a background thread. Wrap in `Task` or call from a `nonisolated` function. On M4 Pro with `.accurate`, expect ~100–200ms per screenshot. With `.fast`, ~10–30ms.

### 3.3 — `AppTracker.swift`

**Responsibility**: Track which applications are running and which is in the foreground. Provides both real-time tracking (via notifications) and snapshot-time queries.

```swift
@MainActor
final class AppTracker: Observable {
    /// The currently active foreground application.
    private(set) var foregroundApp: RunningAppInfo?

    /// Called by CaptureScheduler at snapshot time.
    /// Returns the current foreground app and list of all user-facing running apps.
    func snapshot() -> (foreground: RunningAppInfo, running: [RunningAppInfo])

    /// Starts observing app activation changes for time tracking.
    func startTracking()

    /// Stops observing.
    func stopTracking()
}
```

**Implementation Details**:

1. **Real-time foreground tracking** (for accurate time-tracking):
   - Observe `NSWorkspace.didActivateApplicationNotification`.
   - On each notification, update `foregroundApp` and record the timestamp.
   - Record app switches as `AppUsageRecord` entries in the database (start/end times).

2. **Snapshot-time enumeration** (called every capture cycle):
   - Use `NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }` to get user-facing apps.
   - Use `NSWorkspace.shared.frontmostApplication` for the current foreground app.
   - Map each `NSRunningApplication` to a `RunningAppInfo`.

3. **Window titles** (optional, enriches data):
   - Use `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` to get window titles.
   - Filter by `kCGWindowLayer == 0` for normal windows.
   - Match windows to the foreground app by PID.
   - Note: `kCGWindowName` requires Screen Recording permission.

4. **Excluded apps**: Filter out any apps whose `bundleIdentifier` is in `Configuration.excludedBundleIDs`.

### 3.4 — `ImageProcessor.swift`

**Responsibility**: Resize a CGImage to fit within 1080p bounds and compress to JPEG.

```swift
final class ImageProcessor: Sendable {
    /// Resizes the image so its height ≤ maxHeight, maintaining aspect ratio.
    /// Returns the resized CGImage.
    func resize(_ image: CGImage, maxHeight: Int) -> CGImage?

    /// Compresses a CGImage to JPEG data at the given quality.
    func compressToJPEG(_ image: CGImage, quality: Double) -> Data?
    
    /// Convenience: resize + compress in one call.
    func processForStorage(_ image: CGImage, maxHeight: Int, quality: Double) -> Data?
}
```

**Implementation Details**:

1. **Resize** using `CGContext`:
   - Calculate scale factor: `min(maxWidth / originalWidth, maxHeight / originalHeight)`.
   - For 1080p: `maxHeight = 1080`, `maxWidth = 1920`.
   - If image is already ≤ 1080p, skip resize.
   - Create a `CGContext` with calculated dimensions, `bitsPerComponent: 8`, `CGColorSpaceCreateDeviceRGB()`.
   - Set `context.interpolationQuality = .high`.
   - Draw the source image into the context.
   - Extract the result with `context.makeImage()`.

2. **JPEG compression**:
   - Use `CGImageDestination` (ImageIO framework) for efficient JPEG writing:
     ```swift
     let data = NSMutableData()
     let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
     CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
     CGImageDestinationFinalize(dest)
     ```
   - This is faster and more memory-efficient than going through `NSBitmapImageRep`.

### Phase 3 — Verification

- [ ] `ScreenCapture.captureMainDisplay()` returns a CGImage when permission is granted
- [ ] `OCREngine.recognizeText(in:)` extracts readable text from a test screenshot
- [ ] `AppTracker.snapshot()` returns the correct foreground app and running apps list
- [ ] `ImageProcessor.processForStorage()` produces JPEG data < 300KB for a typical screenshot
- [ ] All operations complete within acceptable time (total < 500ms on M4 Pro)

---

## Phase 4: Storage Layer

**Goal**: Persist snapshots, screenshots, and app usage data. Provide full-text search.

### 4.1 — `DatabaseManager.swift`

**Responsibility**: Own the GRDB `DatabasePool`, run migrations, provide read/write access.

```swift
final class DatabaseManager: Sendable {
    let dbPool: DatabasePool
    
    /// Initialize with path to the SQLite database file.
    init(path: String) throws
    
    /// Run all pending migrations.
    func migrate() throws
}
```

**Implementation Details**:

1. **Database location**: `~/Library/Application Support/com.personalhistorian.app/historian.db`
2. **Use `DatabasePool`** (not `DatabaseQueue`) for WAL mode — allows concurrent reads during writes.
3. **Configuration**:
   ```swift
   var config = Configuration()
   config.prepareDatabase { db in
       db.trace { print("SQL: \($0)") }  // Debug only
   }
   ```

4. **Migrations** (use `DatabaseMigrator`):

**Migration v1 — snapshots table**:
```sql
CREATE TABLE snapshots (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp       DATETIME NOT NULL,
    foregroundApp   TEXT NOT NULL,
    foregroundBundleId TEXT,
    windowTitle     TEXT,
    ocrText         TEXT,
    screenshotPath  TEXT,
    runningAppsJson TEXT,
    UNIQUE(timestamp)
);

CREATE INDEX idx_snapshots_timestamp ON snapshots(timestamp);
CREATE INDEX idx_snapshots_foregroundApp ON snapshots(foregroundApp);
```

**Migration v1 — FTS5 virtual table** (synchronized):
```sql
CREATE VIRTUAL TABLE snapshots_fts USING fts5(
    foregroundApp,
    windowTitle,
    ocrText,
    content='snapshots',
    content_rowid='id',
    tokenize='unicode61'
);

-- Triggers for auto-sync (GRDB's synchronize(withTable:) handles this)
```

**Migration v1 — app_usage table**:
```sql
CREATE TABLE app_usage (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    appName         TEXT NOT NULL,
    bundleIdentifier TEXT,
    startTime       DATETIME NOT NULL,
    endTime         DATETIME,
    durationSeconds REAL
);

CREATE INDEX idx_app_usage_startTime ON app_usage(startTime);
CREATE INDEX idx_app_usage_appName ON app_usage(appName);
```

Use GRDB's `DatabaseMigrator` with `registerMigration("v1")` to define these in Swift.

### 4.2 — `SnapshotRecord.swift`

A GRDB `Record` subclass (or struct conforming to `FetchableRecord, PersistableRecord`):

```swift
struct SnapshotRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?
    var timestamp: Date
    var foregroundApp: String
    var foregroundBundleId: String?
    var windowTitle: String?
    var ocrText: String?
    var screenshotPath: String?      // Relative path from screenshots base dir
    var runningAppsJson: String?     // JSON-encoded [RunningAppInfo]

    static let databaseTableName = "snapshots"
}
```

Include a static method to set up the FTS5 synchronized table using GRDB's API:
```swift
static func configureFTS(_ db: Database) throws {
    try db.create(virtualTable: "snapshots_fts", using: FTS5()) { t in
        t.synchronize(withTable: "snapshots")
        t.column("foregroundApp")
        t.column("windowTitle")
        t.column("ocrText")
        t.tokenizer = .unicode61()
    }
}
```

### 4.3 — `AppUsageRecord.swift`

```swift
struct AppUsageRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?
    var appName: String
    var bundleIdentifier: String?
    var startTime: Date
    var endTime: Date?
    var durationSeconds: Double?

    static let databaseTableName = "app_usage"
}
```

**Write operations**:
- `startSession(app:at:)` — inserts a new row with `endTime = nil`.
- `endSession(id:at:)` — updates `endTime` and computes `durationSeconds`.

**Read operations**:
- `usageByApp(from:to:)` — aggregates `SUM(durationSeconds)` grouped by `appName` for a date range.
- `timeline(from:to:)` — returns all sessions in chronological order for a date range.

### 4.4 — `ScreenshotStorage.swift`

**Responsibility**: Save/load/delete JPEG screenshot files on disk.

```swift
final class ScreenshotStorage: Sendable {
    let baseDirectory: URL  // ~/Library/Application Support/.../screenshots/

    /// Saves JPEG data and returns the relative path for database storage.
    func save(_ data: Data, timestamp: Date, appName: String) throws -> String

    /// Returns the full URL for a relative screenshot path.
    func fullURL(for relativePath: String) -> URL

    /// Deletes a screenshot file.
    func delete(relativePath: String) throws

    /// Deletes all screenshots older than the given date.
    func cleanup(olderThan date: Date) throws

    /// Returns total disk usage of the screenshots directory in bytes.
    func totalDiskUsage() throws -> UInt64
}
```

**Directory structure**:
```
screenshots/
└── 2026/
    └── 06/
        └── 08/
            ├── 111547_Safari.jpg
            ├── 111647_Xcode.jpg
            └── ...
```

**File naming**: `HHmmss_AppName.jpg` (time-only since date is in the directory path). Sanitize app name by replacing `/`, `:`, and other filesystem-unfriendly characters.

**Relative paths** stored in DB: `2026/06/08/111547_Safari.jpg` — this decouples the base directory from the stored data.

### 4.5 — `SearchService.swift`

**Responsibility**: Provide full-text search across snapshot history.

```swift
final class SearchService: Sendable {
    let dbPool: DatabasePool

    /// Search snapshots by text query. Returns most recent matches first.
    func search(query: String, limit: Int = 50) throws -> [SnapshotRecord]

    /// Search within a date range.
    func search(query: String, from: Date, to: Date, limit: Int = 50) throws -> [SnapshotRecord]

    /// Get snapshots for a specific app.
    func snapshots(forApp appName: String, limit: Int = 50) throws -> [SnapshotRecord]

    /// Get all snapshots in a time range (for timeline view).
    func snapshots(from: Date, to: Date) throws -> [SnapshotRecord]
}
```

**FTS5 search query**:
```sql
SELECT snapshots.*
FROM snapshots
JOIN snapshots_fts ON snapshots_fts.rowid = snapshots.id
WHERE snapshots_fts MATCH ?
ORDER BY snapshots.timestamp DESC
LIMIT ?
```

Use `FTS5Pattern(matchingAllPrefixesIn: query)` so partial words work (e.g., "slac" matches "Slack").

### Phase 4 — Verification

- [ ] Database creates successfully at the expected path
- [ ] Migrations run without errors
- [ ] SnapshotRecord insert/fetch round-trips correctly
- [ ] FTS5 search returns relevant results for OCR text queries
- [ ] ScreenshotStorage saves files in the correct directory structure
- [ ] Cleanup correctly removes old files
- [ ] AppUsageRecord correctly computes durations

---

## Phase 5: Capture Scheduler (Orchestration)

**Goal**: Tie the capture pipeline and storage layer together into a reliable, performant capture loop.

### 5.1 — `CaptureScheduler.swift`

**Responsibility**: Run the capture→process→store pipeline at the configured interval.

```swift
@MainActor
final class CaptureScheduler: Observable {
    private(set) var isRunning: Bool = false
    private(set) var lastCaptureTime: Date?
    private(set) var lastError: Error?
    private(set) var captureCount: Int = 0

    private var captureTask: Task<Void, Never>?

    private let screenCapture: ScreenCapture
    private let ocrEngine: OCREngine
    private let appTracker: AppTracker
    private let imageProcessor: ImageProcessor
    private let databaseManager: DatabaseManager
    private let screenshotStorage: ScreenshotStorage
    private let configuration: Configuration

    func start()
    func stop()
    func captureNow() async  // Manual single capture (for testing)
}
```

**Pipeline per cycle** (see ARCHITECTURE.md for data flow diagram):

```
1. Timer fires
2. IN PARALLEL:
   a. Capture screenshot (ScreenCaptureKit, ~50ms)
   b. Snapshot running apps (NSWorkspace, <1ms)
3. THEN IN PARALLEL (using the captured screenshot):
   a. OCR on full-res image (Vision, ~100-200ms)
   b. Resize to 1080p + compress to JPEG (CoreGraphics, ~30ms)
4. THEN (sequential, all data ready):
   a. Save JPEG to disk (~5ms)
   b. Insert SnapshotRecord to database (~1ms)
5. Log success, update lastCaptureTime
```

**Implementation pattern** using `async let` for parallelism:

```swift
private func executeCaptureLoop() async {
    while !Task.isCancelled {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            try await performSingleCapture()
        } catch {
            self.lastError = error
            // Log but don't crash — next cycle will retry
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let sleepDuration = max(0, Double(configuration.captureIntervalSeconds) - elapsed)
        try? await Task.sleep(for: .seconds(sleepDuration))
    }
}

private nonisolated func performSingleCapture() async throws {
    // Step 1+2: Capture + snapshot apps (parallel)
    async let screenshotTask = screenCapture.captureMainDisplay()
    let appSnapshot = await MainActor.run { appTracker.snapshot() }
    let screenshot = try await screenshotTask

    // Step 3: OCR + resize (parallel)
    async let ocrTask = ocrEngine.recognizeText(
        in: screenshot,
        level: configuration.ocrVNLevel
    )
    async let imageTask = imageProcessor.processForStorage(
        screenshot,
        maxHeight: configuration.maxResolutionHeight,
        quality: configuration.imageQuality
    )

    let ocrText = try await ocrTask
    guard let jpegData = await imageTask else {
        throw CaptureError.imageProcessingFailed
    }

    // Step 4: Save to disk + database (sequential)
    let relativePath = try screenshotStorage.save(
        jpegData,
        timestamp: Date(),
        appName: appSnapshot.foreground.name
    )

    let record = SnapshotRecord(
        timestamp: Date(),
        foregroundApp: appSnapshot.foreground.name,
        foregroundBundleId: appSnapshot.foreground.bundleIdentifier,
        windowTitle: nil, // populated if CGWindowList was used
        ocrText: ocrText,
        screenshotPath: relativePath,
        runningAppsJson: encodeJSON(appSnapshot.running)
    )

    try await databaseManager.dbPool.write { db in
        try record.insert(db)
    }
}
```

**Critical performance rules**:
1. **Never block the main thread**. The entire pipeline runs in a `Task` (cooperative thread pool). Only `appTracker.snapshot()` touches the main actor (and it's sub-millisecond).
2. **Use `async let` for parallelism** where inputs are independent.
3. **Account for pipeline duration** in the sleep interval — subtract elapsed time from the configured interval.
4. **Swallow individual capture errors** — log them but keep the loop running.
5. **Check `Task.isCancelled`** to support clean shutdown.

### 5.2 — Retention Cleanup

Add a daily cleanup task to `CaptureScheduler` (or `AppState`):

```swift
private func scheduleCleanup() {
    Task {
        while !Task.isCancelled {
            if configuration.retentionDays > 0 {
                let cutoff = Calendar.current.date(
                    byAdding: .day,
                    value: -configuration.retentionDays,
                    to: Date()
                )!
                try? screenshotStorage.cleanup(olderThan: cutoff)
                try? await databaseManager.deleteSnapshots(olderThan: cutoff)
            }
            try? await Task.sleep(for: .seconds(86400)) // Run once per day
        }
    }
}
```

### Phase 5 — Verification

- [ ] Capture loop fires at the configured interval (±1 second tolerance)
- [ ] Full pipeline completes in < 500ms on M4 Pro
- [ ] No main-thread hangs during capture (test with Instruments Time Profiler)
- [ ] Errors in one cycle don't stop subsequent cycles
- [ ] Stop/start correctly cancels and resumes the loop
- [ ] Retention cleanup removes old screenshots and database records

---

## Phase 6: User Interface

**Goal**: Minimal but functional menu bar UI with search and settings.

### 6.1 — `PersonalHistorianApp.swift` (full implementation)

```swift
@main
struct PersonalHistorianApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Personal Historian", systemImage: "clock.arrow.circlepath") {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window) // Rich content dropdown

        // Search window (opened from menu bar)
        Window("Search History", id: "search") {
            SearchView()
                .environment(appState)
        }
        .defaultSize(width: 800, height: 600)

        // Settings window
        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
```

### 6.2 — `MenuBarView.swift`

The menu bar dropdown should show:

1. **Status indicator**: "● Recording" (green dot) or "○ Paused" (gray)
2. **Last capture time**: "Last capture: 30 seconds ago"
3. **Today's stats** (derived from database):
   - Total captures today
   - Top 3 apps by usage time
4. **Divider**
5. **Actions**:
   - "Pause/Resume Recording" toggle
   - "Capture Now" (manual trigger)
   - "Search History..." (opens search window)
6. **Divider**
7. **Settings...** (opens settings window via `NSApp.sendAction(Selector(("showSettingsWindow:")))`)
8. **Quit Personal Historian**

Keep the menu bar view lightweight — no heavy queries on open. Cache today's stats and update them after each capture.

### 6.3 — `SearchView.swift`

A full window for searching capture history:

1. **Search bar** at the top with live-as-you-type filtering (debounce 300ms).
2. **Results list** showing:
   - Thumbnail of the screenshot (lazy-loaded)
   - Timestamp (human-readable: "Today 2:35 PM" or "Jun 7, 3:12 PM")
   - Foreground app name + icon (from bundle ID)
   - Preview of OCR text (first 100 chars, with search term highlighted)
3. **Detail panel** (click a result):
   - Full-size screenshot
   - Complete OCR text
   - List of all running apps at that moment

Use a `NavigationSplitView` with a sidebar list and detail pane.

**Performance**: Use `LazyVStack` for the results list. Load thumbnails asynchronously. Limit initial query to 50 results with "Load More" pagination.

### 6.4 — `SettingsView.swift`

A standard macOS settings window (`Settings` scene) with tabs/sections:

1. **General**:
   - Capture interval slider (10s – 300s, step 10s)
   - Launch at login toggle (uses `SMAppService`)
   - Recording on/off toggle
2. **Storage**:
   - Screenshot quality slider (0.3 – 1.0)
   - Retention period picker (7, 14, 30, 60, 90 days, Forever)
   - Current disk usage display
   - "Open Storage Folder" button
   - "Delete All Data" button (with confirmation)
3. **Privacy**:
   - Excluded apps list (add/remove bundle IDs)
   - Screen recording permission status + "Open System Settings" button
4. **Advanced**:
   - OCR recognition level picker (Fast / Accurate)
   - Max screenshot resolution

### 6.5 — `PermissionGuideView.swift`

A one-time onboarding sheet shown when screen recording permission hasn't been granted:

1. Explain what the app does and why it needs screen recording.
2. "Grant Permission" button → calls `CGRequestScreenCaptureAccess()`.
3. After granting, instruct user to restart the app (macOS requirement).
4. "Open System Settings" fallback link.

Show this automatically on first launch or when permission check fails.

### Phase 6 — Verification

- [ ] Menu bar dropdown displays recording status and stats
- [ ] Pause/Resume toggle works and is reflected in the icon
- [ ] Search window opens, performs searches, shows results
- [ ] Clicking a search result shows the screenshot and details
- [ ] Settings changes take effect immediately (capture interval, quality, etc.)
- [ ] Launch at login toggle works correctly
- [ ] Permission guide appears when needed

---

## Phase 7: Polish & Error Handling

**Goal**: Production-quality reliability, logging, and edge-case handling.

### 7.1 — Logging

Use `os.Logger` throughout:

```swift
import os

extension Logger {
    static let capture = Logger(subsystem: "com.personalhistorian.app", category: "capture")
    static let storage = Logger(subsystem: "com.personalhistorian.app", category: "storage")
    static let ocr = Logger(subsystem: "com.personalhistorian.app", category: "ocr")
}
```

Log at appropriate levels:
- `.debug` — Pipeline timing, individual step durations
- `.info` — Capture completed, file saved
- `.error` — Capture failed, permission denied, disk full
- `.fault` — Unrecoverable errors (database corruption)

### 7.2 — Error Handling Strategy

| Error | Response |
|-------|----------|
| Screen recording permission denied | Show PermissionGuideView, pause recording |
| ScreenCaptureKit capture fails | Log error, skip cycle, retry next interval |
| OCR fails | Save snapshot without OCR text (set `ocrText = ""`) |
| JPEG compression fails | Log error, skip cycle |
| Disk full / write fails | Pause recording, show alert in menu bar, log error |
| Database write fails | Log error, retry once, then skip |
| App crash during capture | On next launch, detect incomplete state, resume normally |

### 7.3 — Performance Monitoring

Add timing instrumentation to the capture pipeline:

```swift
let metrics = CaptureMetrics(
    captureMs: ...,
    ocrMs: ...,
    resizeMs: ...,
    saveMs: ...,
    totalMs: ...
)
Logger.capture.debug("Capture completed: \(metrics)")
```

If `totalMs` consistently exceeds 50% of the capture interval, log a warning suggesting the user increase the interval.

### 7.4 — Graceful Shutdown

In `AppState` or `AppDelegate`:
1. On `applicationWillTerminate`: stop the capture scheduler, flush pending database writes.
2. End any open `AppUsageRecord` sessions with the current timestamp.

### 7.5 — Sleep/Wake Handling

Observe `NSWorkspace.willSleepNotification` and `didWakeNotification`:
- On sleep: pause the capture loop (no point capturing a sleeping screen).
- On wake: resume after a short delay (2–3 seconds for screen to stabilize).

### 7.6 — Screen Lock Detection

Observe `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` distributed notifications:
- On lock: pause captures (screen content is the lock screen — not useful).
- On unlock: resume captures.

### Phase 7 — Verification

- [ ] Logs appear in Console.app with correct subsystem/category
- [ ] App recovers gracefully from all error scenarios in the table above
- [ ] App pauses on sleep and resumes on wake
- [ ] App pauses on screen lock and resumes on unlock
- [ ] App shuts down cleanly with no data loss
- [ ] No memory leaks during extended operation (verify with Instruments)

---

## Phase 8: Testing & Final Verification

### 8.1 — Unit Tests

| Test File | What It Tests |
|-----------|--------------|
| `OCREngineTests.swift` | OCR on a known test image with expected text |
| `ImageProcessorTests.swift` | Resize produces correct dimensions; JPEG data is valid |
| `DatabaseManagerTests.swift` | Migrations, insert/fetch, FTS5 search, app usage aggregation |
| `SearchServiceTests.swift` | FTS5 query patterns, date range filtering, result ordering |
| `CaptureSchedulerTests.swift` | Timer fires at correct intervals, pipeline error isolation |

### 8.2 — Integration Test

A manual or automated test that:
1. Launches the app.
2. Grants screen recording permission.
3. Waits for 3 capture cycles (with interval set to 5 seconds).
4. Verifies 3 snapshots in the database.
5. Verifies 3 JPEG files on disk.
6. Searches for text visible on screen and finds a match.
7. Verifies app usage records exist.

### 8.3 — Performance Benchmarks

Run on the target M4 Pro MacBook:

| Operation | Target | Method |
|-----------|--------|--------|
| Screenshot capture | < 100ms | Instruments / `CFAbsoluteTimeGetCurrent` |
| OCR (accurate) | < 300ms | Instruments |
| OCR (fast) | < 50ms | Instruments |
| Image resize + JPEG | < 50ms | Instruments |
| DB insert | < 5ms | Instruments |
| FTS5 search (10K records) | < 50ms | Benchmark test |
| **Total pipeline** | **< 500ms** | End-to-end measurement |
| Main thread blocked | **0ms** | Time Profiler |

### 8.4 — Storage Verification

After 1 hour of operation at 60-second intervals:
- [ ] ~60 JPEG files exist in the correct directory structure
- [ ] ~60 snapshot records in the database
- [ ] Total disk usage ≈ 12–18 MB (reasonable for 60 screenshots)
- [ ] FTS5 search works correctly across all records
- [ ] App usage records accurately reflect foreground app time

---

## Implementation Order

For agents working in parallel, the recommended approach:

```
Phase 1 (scaffolding) ─────────────────────────────┐
                                                     │
Phase 2 (models + config) ─────────────────────────┐│
                                                     ││
Phase 3 (capture engines) ──── can start after 2 ──┐││
Phase 4 (storage layer) ────── can start after 2 ──┤││
                                                     │││
Phase 5 (orchestration) ────── needs 3 + 4 ────────┘││
Phase 6 (UI) ──────────────── needs 2 + 4 ──────────┘│
Phase 7 (polish) ──────────── needs 5 + 6 ────────────┘
Phase 8 (testing) ─────────── needs all ───────────────
```

**Parallelizable work**:
- Phase 3 and Phase 4 can be built simultaneously by different agents.
- Phase 6 can begin as soon as Phase 2 is done (using stub services initially).
- Within Phase 3, all four engines are independent of each other.

---

## Open Questions / Decisions for User

1. **Multi-monitor support**: Should the app capture all displays or just the primary display? (Plan assumes primary only.)
2. **HEIC vs JPEG**: HEIC is ~40% smaller but less universally supported. Should we offer HEIC as an option?
3. **Data export**: Should we include a CLI tool or "Export to JSON/CSV" feature in this initial scope?
4. **Menu bar icon**: Custom icon or SF Symbol (`clock.arrow.circlepath`)?
5. **Window titles**: Should we attempt to capture window titles (requires CGWindowList)? This adds richness to search but adds API complexity.
