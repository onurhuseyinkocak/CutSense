# CutSense iOS — Project Rules

## Quality Verification Policy

Claude Code must never mark a feature as complete unless all of these are true:

1. The feature has real implementation code.
2. The feature is wired into the app flow.
3. The feature can be reached from UI or documented execution path.
4. The feature affects final export or database as intended.
5. The feature has error handling.
6. The feature has at least one manual test path.
7. The feature is listed in the progress report with evidence.
8. Placeholder/TODO/mock-only code is not counted as complete.

## Completion Language Rules

- **Implemented** means real and wired.
- **Partial** means some code exists but not fully usable.
- **Stub** means fake or placeholder.
- **Designed** means documented but not coded.
- **Untested** means not verified.

## Phase Completion Requirements

Every phase must include:
- Build result
- Files changed
- Manual test steps
- What was verified
- What was not verified
- Known risks
- Screenshots or logs if applicable

No phase can be marked complete without passing its acceptance criteria.

## Quality Test Harness Rules

Before any TestFlight submission:
1. All tests in `Tests/CutSenseQualityTests/` must pass (`xcodebuild test`)
2. Golden transcript scenarios A-G must all pass
3. `scripts/verify.sh` must exit 0
4. ExportVerificationReport must generate after export (check Documents/CutSense/Reports/)
5. Manual QA checklist score >= 85% (see docs/manual-qa-checklist.md)

### Test Files
- `TestHelpers.swift` — TestFixture factory, never delete
- `GoldenTranscriptTests.swift` — 7 scenarios, add new ones as bugs are found
- `RoughCutModuleTests.swift` — per-component unit tests
- `ExportVerificationTests.swift` — quality gate + export pipeline tests

### Debug Tools
- `Debug/ExportVerificationReport.swift` — JSON report saved after every export
- `Debug/DebugTimelineScreen.swift` — per-segment debug view (shake gesture in dev)

### Adding Pipeline Features
When adding a new caption role, scene behavior, or effect type:
1. Add test case in ExportVerificationTests
2. Add golden scenario if it's a new classification pattern
3. Verify effect appears in ExportVerificationReport
4. Run full test suite before committing
