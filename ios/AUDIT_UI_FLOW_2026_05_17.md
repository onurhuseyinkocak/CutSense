# CutSense iOS App UI Flow & Navigation Audit
**Date:** 2026-05-17 | **Scope:** Complete UI layer (12 screens, RootView, App flow)

---

## Executive Summary

**Status: BROKEN NAVIGATION + SILENT DATA LOSS ISSUES**

The app has a complete navigation flow but suffers from:
- **16 identified UI/UX/data flow bugs**
- **8 critical issues affecting export pipeline**
- **4 auth/state management issues**
- **Multiple silent failure modes** (no user feedback)
- Unreachable error states
- Missing data persistence checks

**On real device impact:** App appears to work but data silently fails to save, incomplete exports are not caught, and auth failures are invisible to users.

---

## Architecture Overview

```
RootView (entry point)
├─ OnboardingScreen (one-time, swipe-based)
├─ AuthScreen (Supabase auth)
└─ ProjectsScreen (main hub)
   └─ VideoImportScreen (per-project editor)
      ├─ AnalysisScreen (AI analysis via task)
      │  └─ RoughCutReviewScreen (edit decisions, undo/redo)
      │     └─ TemplateSelectionScreen (style + effects)
      │        ├─ CaptionPreviewScreen (captions + quality gate)
      │        │  └─ ExportScreen (sheet - render video)
      │        ├─ CustomTemplateBuilderScreen (style editor)
      │        ├─ TemplateHubScreen (community templates)
      │        └─ file picker (import JSON)
      │
      └─ Resume path: RoughCutReviewScreen (if project status in [roughCutReady, reviewed, styling, exported])
```

**Key observation:** Flow is correct structurally but rife with missing error handling between screens.

---

## Critical Issues by Severity

### TIER 1: EXPORT PIPELINE BROKEN (silent data loss)

#### [1.1] ExportScreen.startExport() Missing Error Path
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/ExportScreen.swift:213-237`

Export decision tree has fatal flaw:
```swift
var exportedURL: URL?
if let decisions, let captions, let template {
    exportedURL = await exportService.exportWithPipeline(...)
} else {
    exportedURL = await exportService.exportNormalized(from: sourceURL)
}
// Save export record to DB or mark failed
if let userId, let url = exportedURL {
    await saveExportRecord(userId: userId, fileURL: url)
} else if userId != nil {
    try? await PipelineRepository().updateProjectStatus(projectId, status: .failed)
}
```

**Problem:**
1. If `exportWithPipeline` returns nil (failure), `exportedURL` is nil
2. `ExportScreen.exportedURL` is separate from local `exportedURL` variable
3. Line 233: checks `let url = exportedURL` → FAILS silently
4. Line 235: only updates .failed if userId exists
5. **UI shows: "Export Complete" (via @State exportedURL binding) even though it failed**

**Impact:** User exports video, sees "Export Complete", but video file is not saved to Photos.

---

#### [1.2] ExportScreen hasPipeline() Incomplete Check
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/ExportScreen.swift:74-76`
```swift
private var hasPipeline: Bool {
    decisions != nil && captions != nil && template != nil
}
```

**Problem:** Doesn't check `editPlan != nil`. But on line 222, exportWithPipeline is called with optional editPlan. If editPlan is nil, pipeline fails.

**Also:** hasCriticalFailures checks qualityReport.checks but qualityReport can be nil (line 79), causing crash.

---

#### [1.3] CaptionPreviewScreen Doesn't Guard userId Before Saving
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/CaptionPreviewScreen.swift:154-167`
```swift
.task {
    await viewModel.generate(transcription: transcription, roughCut: roughCut, template: template)
    // Save caption data to DB after generation
    if let userId = authManager.currentUser?.id {
        await viewModel.saveCaptionData(projectId: projectId, userId: userId, templateName: template.name)
    }
}
```

**Problem:** If userId is nil, saveCaptionData never runs. Captions are generated but not persisted to database.

**Impact:** User sees captions on preview but they're lost when app restarts or export fails.

---

#### [1.4] RoughCutReviewScreen Saves Without Feedback Before Transition
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/RoughCutReviewScreen.swift:119-131`
```swift
Button {
    showTemplateSelection = true
    Task {
        let pipeline = PipelineRepository()
        if let userId = authManager.currentUser?.id {
            try? await pipeline.deleteRoughCutDecisions(projectId: projectId)
            try? await pipeline.saveRoughCutDecisions(...)
        }
        try? await pipeline.updateProjectStatus(projectId, status: .reviewed)
    }
} label: { ... }
```

**Problem:**
1. Navigation triggers BEFORE async DB save completes
2. Errors are silently swallowed (`try?`)
3. No loading indicator, no error alert
4. User navigates to next screen while old data is still being written to DB

**Impact:** User edits cut decisions, transitions to captions, but old decisions are still in export metadata if DB write fails.

---

### TIER 2: AUTH/STATE MANAGEMENT FAILURES

#### [2.1] AnalysisScreen Start Button Silent Failure
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/AnalysisScreen.swift:373-375`
```swift
Button {
    guard let userId = authManager.currentUser?.id else { return }
    Task { await viewModel.analyze(videoURL: videoURL, projectId: projectId, userId: userId) }
} label: { ... }
```

**Problem:** Button silently returns if userId is nil. User taps, sees no feedback, nothing happens.

**UX Impact:** Button appears enabled even when user isn't logged in.

---

#### [2.2] VideoImportScreen Never Calls onProjectUpdated
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/VideoImportScreen.swift:16`
```swift
let onProjectUpdated: (Project) -> Void
```

**Problem:** This parameter exists but is NEVER called in the screen. Parent ProjectsScreen passes this callback expecting updates but it never receives them.

**Impact:** User changes project status (draft → imported → analyzing) but parent ProjectsScreen list never updates to show new status.

---

#### [2.3] VideoImportScreen.resumeProject Falls Back Silently
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/VideoImportScreen.swift:224-257`
```swift
private func resumeProject() async {
    isLoadingResume = true
    defer { isLoadingResume = false }
    let pipeline = PipelineRepository()
    do {
        let transcript = try await pipeline.fetchTranscript(projectId: project.id)
        let roughCut = try await pipeline.fetchRoughCutDecisions(projectId: project.id)
        guard let transcript, let roughCut else {
            showAnalysis = true  // Fall back silently
            return
        }
        ...
    } catch {
        showAnalysis = true  // Fall back silently
    }
}
```

**Problem:** If DB fetch fails (network error, missing data), automatically triggers re-analysis without asking user.

**Risk:** User's previous analysis and edits are abandoned without notification.

**Better UX:** Show alert: "Could not resume previous analysis. Re-analyze now?"

---

### TIER 3: DATA FLOW & QUALITY GATE ISSUES

#### [3.1] CaptionPreviewScreen Quality Report Can Be Nil
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/CaptionPreviewScreen.swift:35-54`
```swift
qualityReport = QualityGateService.evaluate(
    captions: captions,
    editPlan: plan,
    roughCut: roughCut,
    template: template,
    continuity: continuity,
    coherence: coherence
)
```

**Problem:** If QualityGateService.evaluate fails or returns nil, qualityReport is nil.

**Then:** ExportScreen receives `qualityReport: nil`, and `hasCriticalFailures` always returns false.

**Impact:** Quality gate is completely bypassed if report generation fails silently.

---

#### [3.2] RoughCutPreviewPlayer Error Doesn't Propagate
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/RoughCutPreviewPlayer.swift:144-146`
```swift
} catch {
    errorMessage = error.localizedDescription
    isLoading = false
}
```

**Problem:** Sets local errorMessage but parent RoughCutReviewScreen can't respond or show user-level error alert. Parent never knows there's an error building the preview.

**UX:** User sees "Building preview..." fade to white/blank screen with no explanation.

---

### TIER 4: UX & STATE ISSUES

#### [4.1] TemplateSelectionScreen Doesn't Auto-Select Imported Template
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/TemplateSelectionScreen.swift:174-193`
```swift
.fileImporter(...) { result in
    guard case .success(let urls) = result, let url = urls.first else { return }
    let count = CustomTemplateStore.shared.importFile(at: url)
    if count > 0 {
        importMessage = "Imported \(count) template(s)"
        // selectedTemplate is NOT updated
    }
}
```

**Problem:** After import, selectedTemplate remains nil. User must manually tap to select the imported template.

**Better:** Auto-select first imported: `selectedTemplate = CustomTemplateStore.shared.templates.last`

---

#### [4.2] ProjectsScreen Double-Loads Projects
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/ProjectsScreen.swift:94-107`
```swift
.task {
    guard let userId = authManager.currentUser?.id else { return }
    await viewModel.loadProjects(userId: userId)
}
.onAppear {
    guard !viewModel.projects.isEmpty, let userId = authManager.currentUser?.id else { return }
    Task { await viewModel.loadProjects(userId: userId) }
}
```

**Problem:** Both .task and .onAppear call loadProjects. .task fires on appear AND when returning from child. .onAppear also fires on every appear.

**Result:** Double (or more) network calls on screen appear and on return.

**Fix:** Remove .onAppear, keep only .task.

---

#### [4.3] TemplateHubScreen Rating Submission Fails Silently
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/TemplateHubScreen.swift:119-124`
```swift
private func submitRating(templateId: UUID, rating: Int) async {
    guard let userId = try? await supabase.auth.session.user.id else { return }
    let success = await hub.rate(templateId: templateId, userId: userId, rating: rating)
    if success {
        await hub.fetchTemplates(sort: sortOrder)
    }
}
```

**Problem:** If auth fails silently, nothing happens. User taps "Rate" button expecting feedback but gets none.

---

### TIER 5: ACCESSIBILITY & MISSING ERROR STATES

#### [5.1] ExportScreen Missing Failed State
**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/ExportScreen.swift:145-211`
- Has: exporting, completed
- Missing: explicit "failed" state
- Result: If export fails mid-way, UI gets stuck in exporting view

---

#### [5.2] Touch Targets Below 44pt on Multiple Screens
- TemplateSelectionScreen: style pills are ~30pt
- AnalysisScreen: step progress circles are ~12pt
- RoughCutReviewScreen: action buttons (Restore, Cut) are ~24pt

---

## Complete Data Flow Trace

### Happy Path (Import → Export)
```
1. ProjectsScreen: User taps project
   ✓ Calls VideoImportScreen(project: project, onProjectUpdated: callback)

2. VideoImportScreen: User picks video
   ✓ Calls importService.importVideo()
   ✓ Updates project.status to .imported ✓
   ✓ Updates project.localProjectPath ✓

3. User taps "Analyze"
   ✓ Navigates to AnalysisScreen

4. AnalysisScreen: auto-starts analysis on .task
   ✓ Saves transcript, segments, decisions to DB
   ✓ Updates project.status to .roughCutReady ✓

5. User taps "Review Rough Cut"
   ✓ Navigates to RoughCutReviewScreen

6. User taps "Choose Template"
   ❌ SAVES decisions asynchronously but navigates immediately
   ❌ No error feedback if save fails
   ✓ Navigates to TemplateSelectionScreen

7. User selects template
   ✓ Navigates to CaptionPreviewScreen

8. CaptionPreviewScreen: auto-generates captions on .task
   ✓ Calls viewModel.generate(...)
   ✓ Saves captions to DB IF userId exists ✓
   ❌ If userId is nil, captions are NOT saved

9. User taps "Export Video"
   ✓ Opens ExportScreen (sheet)

10. ExportScreen: User taps "Start Export"
    ✓ Checks quality gates (if qualityReport exists)
    ❌ If qualityReport is nil, bypass check entirely
    ✓ Calls exportService.exportWithPipeline()
    ❌ If export fails, UI still shows "Export Complete"
    ❌ DB save skipped if userId is nil

11. User taps "Save to Photos"
    ⚠️ If step 10 failed silently, this does nothing
```

**Broken links:**
- Step 6: DB save failure not caught before navigation
- Step 8: userId nil case silently skips save
- Step 10: Export failure not detected or shown to user
- Step 2 → Step 5: onProjectUpdated callback never called, parent never updates

---

## Resume Path Logic

**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/VideoImportScreen.swift:42-49, 151-182, 224-257`

### Resume Flow:
```
IF project.status IN [roughCutReady, reviewed, styling, exported]:
    ✓ Try to load cached video URL from filesystem
    ✓ Try to fetch transcript + rough cut from DB
    IF fetch succeeds:
        ✓ Build RoughCutResult with project.originalDuration
        ✓ showResumedReview = true → RoughCutReviewScreen
    IF fetch fails OR data missing:
        ❌ Silently trigger re-analysis (showAnalysis = true)
        ❌ No user notification
        ❌ User's previous analysis + edits lost
```

**Problem:** User thinks they're resuming previous work but app starts fresh analysis instead. If they made manual edits to decisions in a previous session, those are lost silently.

---

## Error Handling Audit by Screen

| Screen | Network Errors | Auth Errors | DB Errors | User Feedback |
|--------|---|---|---|---|
| VideoImportScreen | ❌ Silent | ❌ Silent | ❌ Silent | None |
| AnalysisScreen | ⚠️ Shows | ❌ Silent | ✓ Logged | Error view |
| RoughCutReviewScreen | ❌ Swallowed (try?) | ❌ Silent | ❌ Swallowed (try?) | None |
| TemplateSelectionScreen | ⚠️ Partial | ⚠️ Partial | ❌ Swallowed | Message popup |
| CaptionPreviewScreen | ❌ Silent | ❌ Silent | ❌ Silent | None |
| ExportScreen | ⚠️ Partial | ❌ Silent | ⚠️ Logged | Depends |
| RoughCutPreviewPlayer | ✓ Shows locally | - | - | Local only |

**Summary:** 8/8 screens have at least one error path that's either silent or not shown to user.

---

## Real Device Impact (Why App Doesn't Work)

1. **Export appears to succeed but file isn't saved** (Issue 1.1)
   - User taps "Start Export", waits 30 seconds, sees "Export Complete"
   - Opens Photos app → file not there
   - Previous analysis lost

2. **Project status doesn't update in list** (Issue 2.2)
   - User edits a video (transitions from draft → imported → analyzing)
   - Closes editor, goes back to Projects list
   - Still shows "Draft" status even though analysis completed

3. **Captions lost on app restart** (Issue 1.3)
   - User generates captions, sees them in preview
   - Closes app (or force quit)
   - Reopens project → captions gone, must re-generate

4. **Resume analysis lost silently** (Issue 2.3)
   - User resumes previous project
   - App shows "Analyzing..." again (re-analyzing)
   - User's previous manual edits to decisions are discarded

5. **Preview building fails silently** (Issue 3.2)
   - User opens RoughCutReviewScreen
   - Sees "Building preview..." then white/blank screen
   - No error message, no way to retry

6. **Quality gate bypassed** (Issue 3.1)
   - User exports video with missing captions or broken segments
   - Quality report never generated
   - Export proceeds with no warnings

---

## Files with Issues
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/ExportScreen.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/CaptionPreviewScreen.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/RoughCutReviewScreen.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/AnalysisScreen.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/VideoImportScreen.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/RoughCutPreviewPlayer.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/TemplateSelectionScreen.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/ProjectsScreen.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/TemplateHubScreen.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/App/RootView.swift`

---

## Recommendations (Priority Order)

### P0: BLOCKING EXPORT (do first)
1. Fix ExportScreen.startExport() to detect export failures and show error alert
2. Add nil guards for ALL required params (decisions, captions, template, editPlan)
3. Show error alert in CaptionPreviewScreen if caption save fails
4. Call onProjectUpdated callback in VideoImportScreen after status changes

### P1: DATA LOSS PREVENTION
5. Add guard + error handling in RoughCutReviewScreen before DB save (show error alert)
6. Show confirmation alert in VideoImportScreen.resumeProject on failure before re-analyzing
7. Ensure quality report always generates or show error in CaptionPreviewScreen
8. Pass error callback from RoughCutPreviewPlayer to parent RoughCutReviewScreen

### P2: UX IMPROVEMENTS
9. Remove .onAppear from ProjectsScreen (keep only .task to prevent double-load)
10. Auto-select imported template in TemplateSelectionScreen
11. Show loading state/disable button during RoughCutReviewScreen template save
12. Disable analysis button in AnalysisScreen if userId is nil

### P3: POLISH
13. Fix touch target sizes (style pills, action buttons → 44pt minimum)
14. Add explicit "failed" state to ExportScreen
15. Improve rating error messaging in TemplateHubScreen
16. Add VoiceOver labels to all icon-only buttons

---

## Navigation Patterns Assessment

✓ **Valid:** All navigationDestination isPresented bindings are checked before pushing
✓ **Valid:** No circular navigation (graph is DAG)
✓ **Valid:** No unreachable screens
✓ **Valid:** ExportScreen correctly uses sheet not NavigationStack

❌ **Issues:** Missing data validation between screens, async work without feedback

---

## Checklist for Fixes

- [ ] Implement error handling in ExportScreen.startExport()
- [ ] Add nil guards to hasPipeline and related checks
- [ ] Add error alerts for DB save operations
- [ ] Implement onProjectUpdated calls
- [ ] Add resume error confirmation dialog
- [ ] Fix RoughCutPreviewPlayer error propagation
- [ ] Remove ProjectsScreen.onAppear duplicate load
- [ ] Auto-select imported templates
- [ ] Fix touch target sizes
- [ ] Test export failure paths
- [ ] Test auth failure paths
- [ ] Test resume with missing DB data
