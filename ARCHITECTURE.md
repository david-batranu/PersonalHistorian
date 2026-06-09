# Personal Historian — Architecture

## System Overview

Personal Historian is a **macOS menu bar agent app** that passively records the user's desktop activity through periodic screenshots, OCR text extraction, and application tracking. All data is stored locally in SQLite + JPEG files for privacy.

```
┌─────────────────────────────────────────────────────────────┐
│                     Menu Bar UI (SwiftUI)                    │
│   ┌──────────┐  ┌──────────┐  ┌────────────┐  ┌─────────┐  │
│   │ StatusBar │  │ Search   │  │ Settings   │  │ Permis. │  │
│   │   View    │  │ Window   │  │  Window    │  │ Guide   │  │
│   └──────────┘  └──────────┘  └────────────┘  └─────────┘  │
├─────────────────────────────────────────────────────────────┤
│                     AppState (orchestrator)                  │
├───────────────────────┬─────────────────────────────────────┤
│    Capture Pipeline   │           Storage Layer              │
│  ┌─────────────────┐  │  ┌───────────────┐ ┌─────────────┐  │
│  │CaptureScheduler │──┤──│DatabaseManager│ │ Screenshot  │  │
│  │ (timer loop)    │  │  │ (GRDB/SQLite) │ │  Storage    │  │
│  └───────┬─────────┘  │  └───────────────┘ │ (JPEG files)│  │
│          │             │  ┌───────────────┐ └─────────────┘  │
│  ┌───────┴─────────┐  │  │ SearchService │                  │
│  │  ScreenCapture  │  │  │   (FTS5)      │                  │
│  │  OCREngine      │  │  └───────────────┘                  │
│  │  AppTracker     │  │                                      │
│  │  ImageProcessor │  │                                      │
│  └─────────────────┘  │                                      │
└───────────────────────┴─────────────────────────────────────┘
         macOS APIs                    File System
  ┌─────────────────────┐     ┌─────────────────────────────┐
  │ ScreenCaptureKit    │     │ ~/Library/Application Support│
  │ Vision (OCR)        │     │   /com.personalhistorian.app/│
  │ NSWorkspace         │     │     historian.db             │
  │ CGWindowList        │     │     screenshots/             │
  │ SMAppService        │     │       2026/06/08/            │
  └─────────────────────┘     │         111547_Safari.jpg    │
                              └─────────────────────────────┘
```

---

## Capture Pipeline — Data Flow

Each capture cycle follows this flow. Steps connected by `║` are sequential; steps on the same level connected by `═══` are parallel.

```
Timer fires (every N seconds)
│
├══════════════════════════════════╗
│                                  ║
▼                                  ▼
┌────────────────────┐   ┌──────────────────┐
│  ScreenCaptureKit  │   │   NSWorkspace    │
│  captureImage()    │   │   snapshot()     │
│  ~50ms             │   │   <1ms           │
└────────┬───────────┘   └──────┬───────────┘
         │                       │
         │  CGImage (Retina)     │  RunningAppInfo[]
         │                       │  + foreground app
         ├═══════════════════════┤
         │                       │
    ┌────┴────┐            ┌─────┴─────┐
    ▼         ▼            ▼           │
┌────────┐ ┌──────────┐               │
│ Vision │ │ CGContext │               │
│  OCR   │ │  resize   │               │
│~150ms  │ │  ~30ms   │               │
└───┬────┘ └────┬─────┘               │
    │           │                      │
    │  String   │  CGImage (1080p)     │
    │           │                      │
    │           ▼                      │
    │     ┌──────────┐                 │
    │     │ ImageIO  │                 │
    │     │  JPEG    │                 │
    │     │  ~5ms    │                 │
    │     └────┬─────┘                 │
    │          │                       │
    │          │  Data (JPEG bytes)    │
    │          │                       │
    ▼          ▼                       ▼
┌─────────────────────────────────────────┐
│            Storage Layer                │
│                                         │
│  ┌─────────────┐    ┌────────────────┐  │
│  │ FileManager │    │  GRDB/SQLite   │  │
│  │ write JPEG  │    │ INSERT snapshot│  │
│  │   ~5ms      │    │    ~1ms        │  │
│  └─────────────┘    └────────────────┘  │
└─────────────────────────────────────────┘

Total pipeline: ~250ms typical on M4 Pro
Capture interval: 60,000ms
Duty cycle: ~0.4% — negligible system impact
```

---

## Concurrency Model

The app uses **Swift structured concurrency** (async/await) exclusively. No GCD (`DispatchQueue`) is used.

### Thread/Actor Assignment

| Component | Actor/Thread | Rationale |
|-----------|-------------|-----------|
| `PersonalHistorianApp` | `@MainActor` | SwiftUI requirement |
| `AppState` | `@MainActor` | Owns UI-visible state, coordinates services |
| `CaptureScheduler` | `@MainActor` (shell) | Publishes state to UI; pipeline body is `nonisolated` |
| `AppTracker` | `@MainActor` | NSWorkspace notifications deliver on main thread |
| `ScreenCapture` | `Sendable`, no actor | ScreenCaptureKit is async and thread-safe |
| `OCREngine` | `Sendable`, no actor | CPU-intensive; runs on cooperative pool |
| `ImageProcessor` | `Sendable`, no actor | CPU-intensive; runs on cooperative pool |
| `DatabaseManager` | `Sendable`, no actor | GRDB's `DatabasePool` handles its own threading |
| `ScreenshotStorage` | `Sendable`, no actor | FileManager operations are thread-safe |
| `SearchService` | `Sendable`, no actor | Read-only DB access via pool |

### Key Concurrency Patterns

**1. The capture pipeline is `nonisolated`**

The `performSingleCapture()` method must NOT run on `@MainActor`. It should be a `nonisolated` function or be launched in a detached task. This ensures the CPU-intensive OCR and image processing don't touch the main thread.

```swift
// CaptureScheduler (simplified)
@MainActor
func start() {
    captureTask = Task.detached(priority: .utility) { [self] in
        while !Task.isCancelled {
            await self.performSingleCapture()  // nonisolated
            try? await Task.sleep(for: .seconds(interval))
        }
    }
}
```

**2. Parallel sub-tasks with `async let`**

```swift
nonisolated func performSingleCapture() async {
    // These two are independent → run in parallel
    async let screenshot = screenCapture.captureMainDisplay()
    async let apps = appTracker.snapshot()  // hops to MainActor internally

    let image = try await screenshot
    let appInfo = await apps

    // These two depend on `image` but are independent of each other → parallel
    async let ocrText = ocrEngine.recognizeText(in: image, level: .accurate)
    async let jpegData = imageProcessor.processForStorage(image, maxHeight: 1080, quality: 0.7)

    // Wait for both, then store
    let text = try await ocrText
    let data = await jpegData
    // ... save to disk and DB
}
```

**3. Database read/write separation**

GRDB's `DatabasePool` uses WAL mode:
- **Writes** go through `dbPool.write { db in ... }` — serialized, but fast (~1ms per insert).
- **Reads** go through `dbPool.read { db in ... }` — concurrent, never blocked by writes.
- Search queries from the UI never block capture pipeline writes.

---

## Data Model

### Entity-Relationship Diagram

```
┌──────────────────────────────────────────────────┐
│                   snapshots                       │
├──────────────────────────────────────────────────┤
│ id              INTEGER PRIMARY KEY AUTOINCREMENT │
│ timestamp       DATETIME NOT NULL UNIQUE          │
│ foregroundApp   TEXT NOT NULL                      │
│ foregroundBundleId TEXT                            │
│ windowTitle     TEXT                               │
│ ocrText         TEXT                               │
│ screenshotPath  TEXT                               │  ──→ File: screenshots/YYYY/MM/DD/HHmmss_App.jpg
│ runningAppsJson TEXT                               │  ──→ JSON: [{"name":"...","bundleIdentifier":"..."}]
└──────────────────────────────────────────────────┘
         │
         │ FTS5 synchronized
         ▼
┌──────────────────────────────────────────────────┐
│               snapshots_fts (FTS5)                │
├──────────────────────────────────────────────────┤
│ foregroundApp   TEXT                               │
│ windowTitle     TEXT                               │
│ ocrText         TEXT                               │
│ (content='snapshots', content_rowid='id')          │
│ (tokenize='unicode61')                             │
└──────────────────────────────────────────────────┘


┌──────────────────────────────────────────────────┐
│                   app_usage                       │
├──────────────────────────────────────────────────┤
│ id              INTEGER PRIMARY KEY AUTOINCREMENT │
│ appName         TEXT NOT NULL                      │
│ bundleIdentifier TEXT                              │
│ startTime       DATETIME NOT NULL                  │
│ endTime         DATETIME                           │
│ durationSeconds REAL                               │
└──────────────────────────────────────────────────┘
```

### `snapshots` Table

One row per capture cycle. This is the primary data table.

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `id` | INTEGER | NO | Auto-increment primary key |
| `timestamp` | DATETIME | NO | Capture time (ISO 8601). UNIQUE constraint prevents duplicates. |
| `foregroundApp` | TEXT | NO | Display name of the frontmost application |
| `foregroundBundleId` | TEXT | YES | Bundle identifier (e.g., `com.apple.Safari`) |
| `windowTitle` | TEXT | YES | Title of the frontmost window (requires Screen Recording permission) |
| `ocrText` | TEXT | YES | All text recognized by Vision OCR, newline-separated |
| `screenshotPath` | TEXT | YES | Relative path to JPEG file (relative to screenshots base dir) |
| `runningAppsJson` | TEXT | YES | JSON array of `RunningAppInfo` structs |

**Indexes**:
- `idx_snapshots_timestamp` on `(timestamp)` — for date range queries and retention cleanup.
- `idx_snapshots_foregroundApp` on `(foregroundApp)` — for app-specific filtering.

### `snapshots_fts` Virtual Table (FTS5)

Synchronized with `snapshots` via GRDB's `synchronize(withTable:)`. This sets up triggers so that every INSERT/UPDATE/DELETE on `snapshots` automatically updates the FTS index.

**Tokenizer**: `unicode61` — handles Unicode normalization, diacritics removal, and case folding. Good for international text.

**Search patterns supported**:
- Prefix matching: `"slac"` matches "Slack" — use `FTS5Pattern(matchingAllPrefixesIn:)`
- Phrase matching: `"error log"` matches that exact phrase
- Boolean: `"swift AND error"` — matches rows containing both tokens
- Column-specific: `foregroundApp:Safari` — search only app names

### `app_usage` Table

One row per contiguous foreground session of an application. Created/updated by `AppTracker` in real-time using `NSWorkspace.didActivateApplicationNotification`.

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `id` | INTEGER | NO | Auto-increment primary key |
| `appName` | TEXT | NO | Display name |
| `bundleIdentifier` | TEXT | YES | Bundle ID |
| `startTime` | DATETIME | NO | When the app became foreground |
| `endTime` | DATETIME | YES | When the app lost foreground. NULL = currently active. |
| `durationSeconds` | REAL | YES | Computed: `endTime - startTime`. NULL while active. |

**Indexes**:
- `idx_app_usage_startTime` on `(startTime)` — for date range queries.
- `idx_app_usage_appName` on `(appName)` — for per-app aggregation.

### Time-Tracking Queries

These queries enable future dashboard/graph creation:

**Daily usage by app**:
```sql
SELECT appName, SUM(durationSeconds) as totalSeconds
FROM app_usage
WHERE date(startTime) = '2026-06-08'
GROUP BY appName
ORDER BY totalSeconds DESC;
```

**Hourly activity heatmap** (from snapshots):
```sql
SELECT
    strftime('%H', timestamp) as hour,
    COUNT(*) as captureCount,
    COUNT(DISTINCT foregroundApp) as uniqueApps
FROM snapshots
WHERE date(timestamp) = '2026-06-08'
GROUP BY hour
ORDER BY hour;
```

**App usage timeline for a day**:
```sql
SELECT appName, startTime, endTime, durationSeconds
FROM app_usage
WHERE date(startTime) = '2026-06-08'
ORDER BY startTime;
```

**Most used apps this week**:
```sql
SELECT appName, SUM(durationSeconds) / 3600.0 as hours
FROM app_usage
WHERE startTime >= date('now', '-7 days')
GROUP BY appName
ORDER BY hours DESC
LIMIT 10;
```

---

## File Storage Layout

```
~/Library/Application Support/com.personalhistorian.app/
├── historian.db                    ← SQLite database (snapshots, app_usage, FTS5)
├── historian.db-wal                ← WAL file (auto-managed by SQLite)
├── historian.db-shm                ← Shared memory file (auto-managed)
└── screenshots/
    └── 2026/
        └── 06/
            └── 08/
                ├── 111547_Safari.jpg
                ├── 111647_Xcode.jpg
                ├── 111747_Slack.jpg
                └── ...
```

### Path Conventions

- **Database path**: Absolute, determined at launch from `FileManager.urls(for: .applicationSupportDirectory)`.
- **Screenshot paths in database**: Always **relative** to `screenshots/` base directory (e.g., `2026/06/08/111547_Safari.jpg`). This allows the app support directory to be moved without invalidating stored paths.
- **Filename format**: `HHmmss_AppName.jpg` where AppName is sanitized (alphanumeric + hyphens only).
- **Directory hierarchy**: `YYYY/MM/DD/` — one directory per day. This keeps per-directory file counts manageable (~1440 files/day max at 60s intervals).

### Storage Estimates

| Interval | Screenshots/Day | Size/Day (JPEG 0.7) | Size/Week | Size/Month |
|----------|----------------|---------------------|-----------|------------|
| 60s | 1,440 | ~280 MB | ~2 GB | ~8.5 GB |
| 120s | 720 | ~140 MB | ~1 GB | ~4.2 GB |
| 300s | 288 | ~56 MB | ~400 MB | ~1.7 GB |

Database size is negligible (~100 bytes/row → ~50 KB/day).

---

## Permission Model

The app requires exactly **one** macOS permission: **Screen Recording**.

### Permission Flow

```
App Launch
│
├─ Check: CGPreflightScreenCaptureAccess()
│
├─ YES → Start recording normally
│
└─ NO → Show PermissionGuideView
         │
         ├─ User clicks "Grant Permission"
         │   └─ CGRequestScreenCaptureAccess()
         │       ├─ System dialog appears
         │       ├─ User grants → App must restart
         │       └─ User denies → Show "Open System Settings" fallback
         │
         └─ User clicks "Open System Settings"
             └─ NSWorkspace.shared.open(URL("x-apple.systempreferences:..."))
```

### Important Screen Recording Behaviors

1. **First capture attempt without permission**: ScreenCaptureKit returns only the desktop wallpaper (no window content). The app must detect this and prompt the user.
2. **After granting permission**: The app **must be fully restarted** (Cmd+Q, not just close the menu). The TCC database is only re-read on process launch.
3. **macOS 15+ (Sequoia)**: Apple introduced periodic re-prompts for screen recording. The app should gracefully handle temporary permission revocations.
4. **Code signing is mandatory**: TCC only remembers permissions for signed apps. During development, always use at minimum `"Apple Development"` signing.

### No Accessibility Permission Needed

The app does NOT need Accessibility access because:
- It uses `NSWorkspace` (not AX API) for app tracking.
- It uses `CGWindowListCopyWindowInfo` for window enumeration (covered by Screen Recording permission).
- It does NOT simulate input events or read UI element hierarchies.

---

## Performance Strategy

### Budget per Capture Cycle

With a 60-second interval, the pipeline must complete well within that window. Target: **< 500ms** total.

```
┌──────────────────────────────────────────────────────────────┐
│ 60-second capture interval                                    │
│                                                                │
│ ████ pipeline (~250ms)                                         │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ idle     │
│ 0.4% duty cycle                                               │
│                                                                │
│ Pipeline breakdown (parallel where possible):                  │
│ ├─ Screenshot capture:  ████  50ms                            │
│ ├─ App snapshot:        █     <1ms  (parallel with capture)   │
│ ├─ OCR (accurate):      ████████████  150ms                   │
│ ├─ Resize + JPEG:       ███  30ms   (parallel with OCR)      │
│ ├─ File write:          ██  5ms                               │
│ └─ DB insert:           █   1ms                               │
│                                                                │
│ Wall-clock time (with parallelism): ~210ms                    │
└──────────────────────────────────────────────────────────────┘
```

### Performance Rules

1. **Zero main-thread work** in the pipeline. The only main-thread access is `AppTracker.snapshot()` which reads cached `NSWorkspace` state (sub-millisecond).

2. **Pipeline runs at `.utility` QoS**. This tells macOS to schedule the work during idle CPU time and to use efficiency cores when possible:
   ```swift
   Task.detached(priority: .utility) { ... }
   ```

3. **No retina screenshots stored**. The M4 Pro's display is 3024×1964 (Retina). Storing at native resolution would be ~3x larger. Downscaling to 1080p happens before disk write.

4. **JPEG, not PNG**. PNG screenshots are 3-5 MB; JPEG at 0.7 quality is ~200KB with perfectly readable text.

5. **WAL mode for SQLite**. Writes don't block reads. The search UI can query while the pipeline writes.

6. **No redundant captures**. If the screen hasn't changed (e.g., idle screen), we could skip the capture. This is a future optimization — not in scope for v1, but the architecture supports adding a diff check.

### Memory Pressure

Each capture cycle briefly holds:
- 1× full-res CGImage (~24 MB for 3024×1964 RGBA)
- 1× 1080p CGImage (~8 MB)
- 1× JPEG Data (~200 KB)
- 1× OCR text string (~few KB)

Total peak: ~32 MB per cycle. This is released immediately after the cycle completes. With 60s intervals, there's no accumulation. The M4 Pro has 24+ GB RAM — this is negligible.

### Disk I/O

One JPEG write per cycle (~200KB) and one SQLite write (~100 bytes). Total I/O: ~200 KB per minute = ~12 MB per hour. This is far below SSD bandwidth thresholds that would cause system impact.

---

## Sleep, Lock, and Wake Behavior

```
┌──────────┐    sleep      ┌──────────┐    wake     ┌──────────┐
│ Recording ├──────────────▶│  Paused  ├────────────▶│ Recording │
└─────┬────┘               └──────────┘    (3s delay)└──────────┘
      │         lock       ┌──────────┐   unlock
      ├────────────────────▶│  Paused  ├────────────▶│ Recording │
      │                    └──────────┘             └──────────┘
      │     user pause
      ├────────────────────▶│  Paused (manual)  │
      │                    │  (no auto-resume)  │
```

**Notifications to observe**:
- `NSWorkspace.willSleepNotification` → pause capture loop
- `NSWorkspace.didWakeNotification` → resume after 3-second delay
- `NSWorkspace.screensDidSleepNotification` → pause (external displays)
- `DistributedNotificationCenter`: `com.apple.screenIsLocked` → pause
- `DistributedNotificationCenter`: `com.apple.screenIsUnlocked` → resume

**On wake resume**: End any open `AppUsageRecord` sessions at the sleep time, then start a fresh session for whatever app is foreground after wake.

---

## Future Extensibility

The architecture is designed to support these future features without major refactoring:

| Future Feature | How It's Supported |
|---------------|-------------------|
| **Dashboards/graphs** | Data is in SQLite with rich time-tracking queries. Any dashboard tool can connect directly. |
| **JSON/CSV export** | `SearchService` already supports date-range queries. Export is a thin wrapper. |
| **Multi-monitor** | `ScreenCapture` iterates `content.displays` — extend to capture all. |
| **AI summarization** | OCR text is stored per snapshot. Feed to LLM for daily summaries. |
| **Cloud sync** | SQLite + JPEG files can be synced via standard file sync. |
| **Browser tab tracking** | Extend `AppTracker` with browser-specific AppleScript queries. |
| **Idle detection** | Compare consecutive screenshots to skip duplicates. |
| **CLI companion** | `DatabaseManager` and `SearchService` can be used from a CLI target. |
