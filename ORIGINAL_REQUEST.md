# Original User Request

## Initial Request — 2026-06-08T09:07:50Z

# Teamwork Project Prompt

Implement the core background engines for "Personal Historian", a macOS menu bar application that passively records the user's desktop activity through periodic screenshots, OCR text extraction, and application tracking. This implementation will focus on the headless backend (Phases 1-5 of the provided `IMPLEMENTATION_PLAN.md`), leaving the UI for a future iteration.

Working directory: `/Users/david/Work/Projects/personal_historian`
Integrity mode: development

## Requirements

### R1. Project Scaffolding & Models
Generate the project using XcodeGen (`project.yml`) and implement the core data models and configuration state as defined in Phases 1 & 2 of the implementation plan.

### R2. Capture Pipeline
Implement the ScreenCaptureKit, Vision OCR, AppTracker, and ImageProcessor engines (Phase 3).

### R3. Storage Layer
Implement the GRDB SQLite database with FTS5 search and file system storage for screenshots (Phase 4).

### R4. Orchestration
Implement the CaptureScheduler timer loop that ties the pipeline and storage layers together with concurrent tasks (Phase 5).

## Acceptance Criteria

### Automated Verification
- [ ] Running `make generate` and `make build` compiles the project successfully.
- [ ] Unit tests are implemented based on Phase 8 of the plan (e.g., `OCREngineTests`, `ImageProcessorTests`, `DatabaseManagerTests`, `CaptureSchedulerTests`).
- [ ] Running `make test` (or `xcodebuild test`) passes all implemented unit tests without errors.
