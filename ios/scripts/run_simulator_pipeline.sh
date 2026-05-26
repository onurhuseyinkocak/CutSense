#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"

SIMULATOR_ID="${CUTSENSE_SIMULATOR_ID:-}"
BUNDLE_ID="${CUTSENSE_BUNDLE_ID:-com.cutsense.app}"
INPUT_FILE="${1:-/Users/jinx/Downloads/WhatsApp Video 2026-05-23 at 11.20.09.mp4}"
DERIVED_DATA="${CUTSENSE_DERIVED_DATA:-/tmp/CutSenseSimulatorDebugBuild}"
RESULT_DIR="${CUTSENSE_RESULT_DIR:-/tmp/cutsense-simulator-pipeline}"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/CutSense.app"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Input video not found: $INPUT_FILE" >&2
  exit 2
fi

if [[ -z "$SIMULATOR_ID" ]]; then
  SIMULATOR_ID="$(
    xcrun simctl list devices booted \
      | sed -nE 's/.*\\(([0-9A-F-]{36})\\).*Booted.*/\\1/p' \
      | head -1
  )"
fi

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "No booted simulator found. Set CUTSENSE_SIMULATOR_ID or boot a simulator." >&2
  exit 4
fi

rm -rf "$RESULT_DIR/appdata"
rm -f "$RESULT_DIR/contact_sheet_1fps.jpg" "$RESULT_DIR/pipeline_assertion_status"
mkdir -p "$RESULT_DIR"

echo "== Simulator =="
xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b

echo "== Build Debug Simulator =="
if [[ "${CUTSENSE_SKIP_BUILD:-0}" != "1" ]]; then
  xcodebuild build \
    -project "$IOS_DIR/CutSense.xcodeproj" \
    -scheme CutSense \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO
else
  echo "Skipping build because CUTSENSE_SKIP_BUILD=1"
fi

echo "== Install =="
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_ID" "$BUNDLE_ID" data)"
xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
rm -rf "$CONTAINER/Library/Application Support/CutSense" "$CONTAINER/tmp/CutSense"
mkdir -p "$CONTAINER/Documents"
cp "$INPUT_FILE" "$CONTAINER/Documents/cutsense_debug_input.mp4"

echo "== Launch Debug Autorun =="
SIMCTL_CHILD_CUTSENSE_DEBUG_FORCE_PRO=1 \
SIMCTL_CHILD_CUTSENSE_DEBUG_FORCE_PIPELINE=1 \
SIMCTL_CHILD_CUTSENSE_DEBUG_RESET_PIPELINE=1 \
SIMCTL_CHILD_CUTSENSE_DEBUG_AUTORUN_PIPELINE=1 \
SIMCTL_CHILD_CUTSENSE_DEBUG_SYNTHETIC_TRANSCRIPT="${CUTSENSE_DEBUG_SYNTHETIC_TRANSCRIPT:-0}" \
SIMCTL_CHILD_CUTSENSE_DEBUG_EXPORT_ON_QUALITY_FAIL="${CUTSENSE_DEBUG_EXPORT_ON_QUALITY_FAIL:-0}" \
SIMCTL_CHILD_CUTSENSE_DEBUG_INPUT_FILE=cutsense_debug_input.mp4 \
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" "$BUNDLE_ID"

echo "== Wait For Export =="
WAIT_SECONDS="${CUTSENSE_PIPELINE_WAIT_SECONDS:-420}"
WAIT_DEADLINE=$((SECONDS + WAIT_SECONDS))
EXPORT_WAIT_STATUS="timeout"
LAST_WAIT_MESSAGE=""
while (( SECONDS < WAIT_DEADLINE )); do
  WAIT_RESULT="$(
    python3 - <<'PY' "$CONTAINER"
import json
import pathlib
import sys

container = pathlib.Path(sys.argv[1])
events_path = container / "Library/Application Support/CutSense/PipelineDiagnostics/pipeline-events.jsonl"
if not events_path.exists():
    print("waiting:no diagnostics yet")
    raise SystemExit(0)

last_export = None
last_any_failed = None
last_completed_stage = None
for raw_line in events_path.read_text().splitlines():
    try:
        event = json.loads(raw_line)
    except json.JSONDecodeError:
        continue
    if event.get("status") == "completed":
        last_completed_stage = event
    if event.get("status") == "failed":
        last_any_failed = event
    if event.get("stage") == "exported":
        last_export = event

event = last_export or last_any_failed or last_completed_stage
if event is None:
    print("waiting:no pipeline event yet")
    raise SystemExit(0)

stage = event.get("stage") or "unknown"
status = event.get("status") or "unknown"
message = event.get("message") or ""
duration = event.get("durationSeconds")
duration_text = f" duration={duration:.1f}s" if isinstance(duration, (int, float)) else ""
print(f"{status}:{stage}:{message}{duration_text}")
PY
  )"
  if [[ "$WAIT_RESULT" != "$LAST_WAIT_MESSAGE" ]]; then
    echo "$WAIT_RESULT"
    LAST_WAIT_MESSAGE="$WAIT_RESULT"
  fi

  if [[ "$WAIT_RESULT" == completed:exported:* ]]; then
    EXPORT_WAIT_STATUS="completed"
    break
  fi
  if [[ "$WAIT_RESULT" == failed:* ]]; then
    EXPORT_WAIT_STATUS="failed"
    break
  fi
  sleep 5
done

if [[ "$EXPORT_WAIT_STATUS" != "completed" ]]; then
  echo "Export wait ended with status: $EXPORT_WAIT_STATUS after ${WAIT_SECONDS}s" >&2
fi

echo "== Pull Artifacts =="
rm -rf "$RESULT_DIR/appdata"
mkdir -p "$RESULT_DIR/appdata"
if [[ -d "$CONTAINER/Library/Application Support/CutSense" ]]; then
  ditto "$CONTAINER/Library/Application Support/CutSense" "$RESULT_DIR/appdata/CutSense"
fi
if [[ -d "$CONTAINER/tmp/CutSense" ]]; then
  ditto "$CONTAINER/tmp/CutSense" "$RESULT_DIR/appdata/tmp-CutSense"
fi

ASSERTION_STATUS_FILE="$RESULT_DIR/pipeline_assertion_status"
rm -f "$ASSERTION_STATUS_FILE"
python3 - <<'PY' "$RESULT_DIR" "$ASSERTION_STATUS_FILE"
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
status_file = pathlib.Path(sys.argv[2])
assertion_failures = []

events = sorted(root.rglob("pipeline-events.jsonl"))
if events:
    print("== Diagnostics ==")
    for line in events[-1].read_text().splitlines():
        event = json.loads(line)
        print(json.dumps({
            "stage": event.get("stage"),
            "status": event.get("status"),
            "message": event.get("message"),
            "artifactCount": event.get("artifactCount"),
            "durationSeconds": event.get("durationSeconds"),
            "metadata": event.get("metadata"),
        }, ensure_ascii=False))

artifacts = sorted(root.rglob("PipelineArtifacts/*.json"))
if not artifacts:
    print("No pipeline artifact JSON found.", file=sys.stderr)
    status_file.write_text("3")
    raise SystemExit(0)

artifact = max(artifacts, key=lambda path: path.stat().st_mtime)
data = json.loads(artifact.read_text())
export = data.get("export") or {}
quality = export.get("qualityReport") or data.get("qualityReport") or {}
verification = export.get("verificationReport") or {}

local_name = export.get("localFileName")
file_path = export.get("filePath")
export_matches = []
if local_name:
    export_matches = sorted(root.rglob(f"exports/{local_name}"))
elif file_path:
    export_matches = sorted(root.rglob(f"exports/{pathlib.Path(file_path).name}"))

if not export:
    assertion_failures.append("export artifact missing")
if not export_matches:
    assertion_failures.append("export file missing from pulled app container")
if export.get("templateName") != "Tech Influencer":
    assertion_failures.append(f"unexpected template {export.get('templateName')!r}")
if quality.get("passed") is not True:
    assertion_failures.append("quality gate did not pass")
if verification.get("passed") is not True:
    assertion_failures.append("post-export verification did not pass")
if verification.get("hasAudioTrack") is not True:
    assertion_failures.append("audio track missing")
if verification.get("audioRMSDBFS") is None or verification.get("audioRMSDBFS") < -55:
    assertion_failures.append(f"audio RMS too low {verification.get('audioRMSDBFS')!r}")
if verification.get("audioPeakDBFS") is None or verification.get("audioPeakDBFS") < -45:
    assertion_failures.append(f"audio peak too low {verification.get('audioPeakDBFS')!r}")
if verification.get("hasVideoTrack") is not True:
    assertion_failures.append("video track missing")
if len(data.get("captions") or []) <= 0:
    assertion_failures.append("captions missing")
if len((data.get("editPlan") or {}).get("decisions") or []) <= 0:
    assertion_failures.append("edit decisions missing")
if verification.get("expectedResolution") and verification.get("resolution") != verification.get("expectedResolution"):
    assertion_failures.append(
        f"resolution {verification.get('resolution')!r} != expected {verification.get('expectedResolution')!r}"
    )

print("== Summary ==")
print("artifact=", artifact)
print("export=", export.get("filePath"))
print("template=", export.get("templateName"))
print("quality_passed=", quality.get("passed"), "score=", quality.get("score"))
print("failed_checks=", quality.get("failedChecks"))
print("verification_passed=", verification.get("passed"))
print("verification_resolution=", verification.get("resolution"), "expected=", verification.get("expectedResolution"))
print("verification_audio=", verification.get("hasAudioTrack"), "video=", verification.get("hasVideoTrack"))
print("verification_audio_levels=", "rms=", verification.get("audioRMSDBFS"), "peak=", verification.get("audioPeakDBFS"), "samples=", verification.get("audioSampleCount"))
print("transcript_conf=", (data.get("transcription") or {}).get("overallConfidence"))
print("captions=", len(data.get("captions") or []))
print("edit_decisions=", len((data.get("editPlan") or {}).get("decisions") or []))
if assertion_failures:
    print("pipeline_assertion_failures=", "; ".join(assertion_failures), file=sys.stderr)
    status_file.write_text("6")
else:
    status_file.write_text("0")
PY

EXPORT_FILE="$(
python3 - <<'PY' "$RESULT_DIR"
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
artifacts = sorted(root.rglob("PipelineArtifacts/*.json"))
if artifacts:
    artifact = max(artifacts, key=lambda path: path.stat().st_mtime)
    data = json.loads(artifact.read_text())
    export = data.get("export") or {}
    for value in (export.get("localFileName"), export.get("filePath")):
        if not value:
            continue
        matches = sorted(root.rglob(f"exports/{pathlib.Path(value).name}"))
        if matches:
            print(matches[-1])
            raise SystemExit

exports = sorted(root.rglob("exports/export_*.mp4"), key=lambda path: path.stat().st_mtime)
if exports:
    print(exports[-1])
PY
)"

if [[ -n "$EXPORT_FILE" ]]; then
  echo "== Media Probe =="
  ffprobe -v error -show_entries format=duration,size:stream=index,codec_type,codec_name,width,height,avg_frame_rate,channels,sample_rate -of json "$EXPORT_FILE" || true
  ffmpeg -hide_banner -nostats -i "$EXPORT_FILE" -af volumedetect -vn -f null - 2>&1 | grep -E 'mean_volume|max_volume' || true
  ffmpeg -hide_banner -y -i "$EXPORT_FILE" -vf fps=1,scale=216:-1,tile=7x5 "$RESULT_DIR/contact_sheet_1fps.jpg" >/dev/null 2>&1 || true
  echo "export_file=$EXPORT_FILE"
  [[ -f "$RESULT_DIR/contact_sheet_1fps.jpg" ]] && echo "contact_sheet=$RESULT_DIR/contact_sheet_1fps.jpg"
fi

if [[ -f "$ASSERTION_STATUS_FILE" ]]; then
  ASSERTION_STATUS="$(cat "$ASSERTION_STATUS_FILE")"
  if [[ "$ASSERTION_STATUS" != "0" ]]; then
    exit "$ASSERTION_STATUS"
  fi
fi
