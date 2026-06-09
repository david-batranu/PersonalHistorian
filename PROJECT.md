# Project: Personal Historian
# Scope: Headless Backend (Phases 1-5)

## Architecture
- Single-process menu bar agent app for macOS.
- **Data Flow**: Timer (CaptureScheduler) triggers ScreenCapture and AppTracker -> OCR and Image processing -> saves to GRDB and file system.
- **Module Boundaries**:
  - `App/`: App lifecycle and AppState.
  - `Models/`: Value types (`RunningAppInfo`, `CaptureResult`) and `Configuration`.
  - `Core/`: Capture Pipeline (`ScreenCapture`, `OCREngine`, `AppTracker`, `ImageProcessor`).
  - `Storage/`: `DatabaseManager`, Records, `ScreenshotStorage`, `SearchService`.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Scaffolding & Models | Phase 1 & 2: XcodeGen setup, models, basic @main | none | DONE |
| 2 | Capture Pipeline | Phase 3: ScreenCapture, OCREngine, AppTracker, ImageProcessor | M1 | IN_PROGRESS |
| 3 | Storage Layer | Phase 4: GRDB DatabaseManager, Storage, SearchService | M1 | PLANNED |
| 4 | Orchestration | Phase 5: CaptureScheduler, dual track sync | M2, M3 | PLANNED |

## Interface Contracts
### AppState ↔ Services
- Services are initialized by `AppState` and accessed by views or `CaptureScheduler`.
- Configuration is an `@Observable` class.

### Pipeline ↔ Storage
- Core engines produce `CaptureResult` (with `CGImage`, `RunningAppInfo`, `ocrText`).
- Storage layer consumes it and persists `SnapshotRecord` + JPEG file.

## Code Layout
Follows `IMPLEMENTATION_PLAN.md` exact structure.
- `personal_historian/project.yml`
- `personal_historian/PersonalHistorian/`
  - `App/`, `Core/`, `Storage/`, `Models/`, `Settings/`
- `personal_historian/Tests/PersonalHistorianTests/`
