#!/bin/bash
# CutSense CI verification script
# Run before every commit / TestFlight submission

set -euo pipefail

cd "$(dirname "$0")/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAIL=0

echo "=== CutSense Verification ==="
echo ""

# 1. Generate Xcode project
echo -n "1. XcodeGen... "
if command -v xcodegen &>/dev/null; then
    xcodegen generate --spec project.yml --use-cache 2>/dev/null
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}SKIP (xcodegen not installed)${NC}"
fi

# 2. Build
echo -n "2. Build... "
if xcodebuild build \
    -scheme CutSense \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -quiet 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAIL${NC}"
    FAIL=1
fi

# 3. Tests
echo -n "3. Tests... "
if xcodebuild test \
    -scheme CutSense \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:CutSenseTests \
    -quiet 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAIL${NC}"
    FAIL=1
fi

# 4. Required files check
echo -n "4. Required files... "
MISSING=""
for f in \
    CutSense/RoughCut/RoughCutDecisionEngine.swift \
    CutSense/RoughCut/SmartTranscriptAnalyzer.swift \
    CutSense/RoughCut/ContextAwareEditCommandDetector.swift \
    CutSense/RoughCut/TakeDetectionEngine.swift \
    CutSense/RoughCut/BestTakeSelector.swift \
    CutSense/RoughCut/MeaningPreservationEngine.swift \
    CutSense/RoughCut/ContinuityChecker.swift \
    CutSense/RoughCut/TranscriptCleanupAnalyzer.swift \
    CutSense/Captions/CaptionEngine.swift \
    CutSense/Captions/CaptionModels.swift \
    CutSense/Captions/CaptionRoleClassifier.swift \
    CutSense/Captions/CaptionSceneEventPlanner.swift \
    CutSense/Editing/EditDecisionEngine.swift \
    CutSense/Editing/QualityGateService.swift \
    CutSense/Editing/TemplateConfig.swift \
    CutSense/Export/TimelineMapper.swift \
    CutSense/Export/ExportService.swift \
    CutSense/Export/CaptionOverlayCompositor.swift \
    CutSense/Editing/SFXAssetManager.swift \
    CutSense/Debug/ExportVerificationReport.swift \
    CutSense/Debug/DebugTimelineScreen.swift \
    CutSense/Resources/SFX/whoosh.mp3 \
    CutSense/Resources/SFX/impact.mp3 \
    CutSense/Resources/SFX/pop.mp3 \
    CutSense/Tests/CutSenseQualityTests/TestHelpers.swift \
    CutSense/Tests/CutSenseQualityTests/GoldenTranscriptTests.swift \
    CutSense/Tests/CutSenseQualityTests/RoughCutModuleTests.swift \
    CutSense/Tests/CutSenseQualityTests/ExportVerificationTests.swift; do
    if [ ! -f "$f" ]; then
        MISSING="$MISSING $f"
    fi
done

if [ -z "$MISSING" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}MISSING:${MISSING}${NC}"
    FAIL=1
fi

# 5. No debug prints in release code (excluding Debug/ and Tests/)
echo -n "5. No debug prints... "
DEBUG_PRINTS=$(grep -rn "print(" CutSense/ \
    --include="*.swift" \
    --exclude-dir="Debug" \
    --exclude-dir="Tests" \
    2>/dev/null | grep -v "// debug" | grep -v "#if DEBUG" | head -5 || true)
if [ -z "$DEBUG_PRINTS" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}WARN — found print() in production code${NC}"
fi

# 6. No TODO/FIXME in production
echo -n "6. No TODO/FIXME... "
TODOS=$(grep -rn "TODO\|FIXME\|HACK\|XXX" CutSense/ \
    --include="*.swift" \
    --exclude-dir="Tests" \
    2>/dev/null | head -5 || true)
if [ -z "$TODOS" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}WARN — found TODOs:${NC}"
    echo "$TODOS"
fi

echo ""
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}=== ALL CHECKS PASSED ===${NC}"
    exit 0
else
    echo -e "${RED}=== CHECKS FAILED ===${NC}"
    exit 1
fi
