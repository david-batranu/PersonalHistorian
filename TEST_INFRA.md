# E2E Test Infra: Personal Historian

## Test Philosophy
- Opaque-box, requirement-driven. No dependency on implementation design.
- Methodology: Category-Partition + BVA + Pairwise + Workload Testing.

## Feature Inventory
| # | Feature | Source (requirement) | Tier 1 | Tier 2 | Tier 3 |
|---|---------|---------------------|:------:|:------:|:------:|
| 1 | Configuration & Start | ORIGINAL_REQUEST | 5 | 5 | ✓ |
| 2 | Screenshot Capture | ORIGINAL_REQUEST | 5 | 5 | ✓ |
| 3 | OCR Extraction | ORIGINAL_REQUEST | 5 | 5 | ✓ |
| 4 | Active App Tracking | ORIGINAL_REQUEST | 5 | 5 | ✓ |
| 5 | SQLite & File Storage | ORIGINAL_REQUEST | 5 | 5 | ✓ |

## Test Architecture
- Test runner: `make e2e-test` or `xcodebuild test -scheme PersonalHistorianE2E`
- Test case format: Automated UI/System tests that launch the app, manipulate the environment, and read resulting sqlite/screenshots.
- Directory layout: `Tests/E2ETests/`

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Standard Background Recording | 1, 2, 3, 4, 5 | Low |
| 2 | Heavy Text/OCR Workload | 2, 3, 5 | Medium |
| 3 | Rapid Application Switching | 1, 4, 5 | Medium |
| 4 | Disk Cleanup/Retention | 5 | High |
| 5 | Permission Denied / Error Recovery | 1, 2 | High |

## Coverage Thresholds
- Tier 1: ≥5 per feature
- Tier 2: ≥5 per feature (where boundaries exist)
- Tier 3: pairwise coverage of major feature interactions
- Tier 4: ≥5 realistic application scenarios
