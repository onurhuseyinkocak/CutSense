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
