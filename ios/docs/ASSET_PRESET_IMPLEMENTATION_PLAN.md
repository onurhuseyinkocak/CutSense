# Asset + Preset Implementation Plan

## Architecture Findings

- Import remains local-first through `VideoImportService`, `ProjectRepository`, and `LocalProjectStore`.
- Analysis already produces transcript segments, silence intervals, rough-cut decisions, take groups, and quality reports through `AnalysisViewModel`.
- Captions flow through `CaptionEngine`, `CaptionRoleClassifier`, `CaptionReadabilityGuard`, and `CaptionSceneEventPlanner`.
- Effects currently flow through `EditDecisionEngine` into `ExportService`, then into `CaptionOverlayCompositor`, `SFXAssetManager`, and `BackgroundMusicService`.
- The safest extension point is a central `AssetRegistry` plus an `EditPackageSelection` that both auto presets and manual overrides can feed into the existing caption/edit/export path.

## Implementation Phases

1. Add bundled asset folders, license metadata, and a typed `AssetRegistry`.
2. Add Cinematic and Tech Influencer package selections that map to existing `TemplateConfig` values.
3. Extend `TemplateConfig` with a dedicated Tech Influencer template and safe preset summaries.
4. Extend `EditDecisionEngine` with preset-aware decisions while preserving the existing API.
5. Add black cinematic mode selection, preset summary, manual bottom tray picker, and export summary to `EditScreen`.
6. Feed registry assets into SFX and BGM render paths; keep synthesized BGM as a fallback only.
7. Add tests for registry path validity and preset edit-plan generation.

## Non-Goals

- No full architecture rewrite.
- No new third-party frameworks.
- No paid APIs or authentication-required asset sources.
- No UI-only fake rendering for audio assets: SFX and music must resolve to bundled files.
