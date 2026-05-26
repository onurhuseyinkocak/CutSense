#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"

DEVICE_ID="${CUTSENSE_DEVICE_ID:-00008140-0011694C2629401C}"
BUNDLE_ID="${CUTSENSE_BUNDLE_ID:-com.cutsense.app}"
INPUT_FILE="${1:-/Users/jinx/Downloads/WhatsApp Video 2026-05-23 at 11.20.09.mp4}"
DERIVED_DATA="${CUTSENSE_DERIVED_DATA:-/tmp/CutSenseDeviceDebugBuild}"
RESULT_DIR="${CUTSENSE_RESULT_DIR:-/tmp/cutsense-device-pipeline}"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/CutSense.app"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Input video not found: $INPUT_FILE" >&2
  exit 2
fi

rm -rf "$RESULT_DIR/appdata" "$RESULT_DIR/live-diagnostics"
rm -f "$RESULT_DIR/contact_sheet_1fps.jpg" "$RESULT_DIR/pipeline_assertion_status"
mkdir -p "$RESULT_DIR"

echo "== Device =="
xcrun devicectl list devices
xcrun devicectl device info details --device "$DEVICE_ID" \
  | grep -E 'identifier:|marketingName:|udid:|developerModeStatus:|pairingState:|tunnelState:|osVersionNumber:' || true

if [[ "${CUTSENSE_SKIP_DEVICE_PREFLIGHT:-0}" != "1" ]]; then
  xcrun xcdevice list --timeout 10 > "$RESULT_DIR/xcdevice-list.json"
  python3 - <<'PY' "$RESULT_DIR/xcdevice-list.json" "$DEVICE_ID"
import json
import sys

devices = json.load(open(sys.argv[1]))
requested = sys.argv[2]

matches = [
    device for device in devices
    if requested in {
        str(device.get("identifier", "")),
        str(device.get("name", "")),
    }
]

if not matches:
    print(f"Device not found by xcdevice: {requested}", file=sys.stderr)
    raise SystemExit(4)

device = matches[0]
if not device.get("available", False):
    error = device.get("error") or {}
    print("Device is not available to Xcode.", file=sys.stderr)
    print(f"name={device.get('name')}", file=sys.stderr)
    print(f"identifier={device.get('identifier')}", file=sys.stderr)
    print(f"interface={device.get('interface')}", file=sys.stderr)
    print(f"error={error.get('description', '')}", file=sys.stderr)
    print(f"recovery={error.get('recoverySuggestion', '')}", file=sys.stderr)
    raise SystemExit(5)
PY
fi

echo "== Build Debug iPhoneOS =="
if [[ "${CUTSENSE_SKIP_BUILD:-0}" != "1" ]]; then
  xcodebuild build \
    -project "$IOS_DIR/CutSense.xcodeproj" \
    -scheme CutSense \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA"
else
  echo "Skipping build because CUTSENSE_SKIP_BUILD=1"
fi

echo "== Install =="
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  "$APP_PATH"

echo "== Copy Input To App Container =="
xcrun devicectl device copy to \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source "$INPUT_FILE" \
  --destination "Documents/cutsense_debug_input.mp4"

echo "== Launch Debug Autorun =="
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  --environment-variables "{\"CUTSENSE_DEBUG_FORCE_PRO\":\"1\",\"CUTSENSE_DEBUG_FORCE_PIPELINE\":\"1\",\"CUTSENSE_DEBUG_RESET_PIPELINE\":\"1\",\"CUTSENSE_DEBUG_AUTORUN_PIPELINE\":\"1\",\"CUTSENSE_DEBUG_SYNTHETIC_TRANSCRIPT\":\"${CUTSENSE_DEBUG_SYNTHETIC_TRANSCRIPT:-0}\",\"CUTSENSE_DEBUG_EXPORT_ON_QUALITY_FAIL\":\"${CUTSENSE_DEBUG_EXPORT_ON_QUALITY_FAIL:-0}\",\"CUTSENSE_DEBUG_INPUT_FILE\":\"cutsense_debug_input.mp4\"}" \
  "$BUNDLE_ID"

echo "== Wait For Export =="
WAIT_SECONDS="${CUTSENSE_PIPELINE_WAIT_SECONDS:-420}"
WAIT_DEADLINE=$((SECONDS + WAIT_SECONDS))
EXPORT_WAIT_STATUS="timeout"
LAST_WAIT_MESSAGE=""
while (( SECONDS < WAIT_DEADLINE )); do
  rm -rf "$RESULT_DIR/live-diagnostics"
  mkdir -p "$RESULT_DIR/live-diagnostics"
  xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "Library/Application Support/CutSense/PipelineDiagnostics" \
    --destination "$RESULT_DIR/live-diagnostics" \
    --remove-existing-content true >/dev/null 2>&1 || true

  WAIT_RESULT="$(
    python3 - <<'PY' "$RESULT_DIR/live-diagnostics"
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
events = sorted(root.rglob("pipeline-events.jsonl"))
if not events:
    print("waiting:no diagnostics yet")
    raise SystemExit(0)

last_export = None
last_any_failed = None
last_completed_stage = None
for raw_line in events[-1].read_text().splitlines():
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
xcrun devicectl device copy from \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source "Library/Application Support/CutSense" \
  --destination "$RESULT_DIR/appdata" \
  --remove-existing-content true || true
if [[ "${CUTSENSE_SKIP_TMP_PULL:-0}" == "1" ]]; then
  echo "Skipping tmp/CutSense pull because CUTSENSE_SKIP_TMP_PULL=1"
else
  xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "tmp/CutSense" \
    --destination "$RESULT_DIR/appdata" \
    --remove-existing-content false || true
fi

ASSERTION_STATUS_FILE="$RESULT_DIR/pipeline_assertion_status"
rm -f "$ASSERTION_STATUS_FILE"
python3 - <<'PY' "$RESULT_DIR" "$ASSERTION_STATUS_FILE" "${CUTSENSE_SKIP_TMP_PULL:-0}"
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
status_file = pathlib.Path(sys.argv[2])
skip_tmp_pull = sys.argv[3] == "1"
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
if not export_matches and not skip_tmp_pull:
    assertion_failures.append("export file missing from pulled app container")
elif not export_matches and skip_tmp_pull:
    print("export_file_pull= skipped because CUTSENSE_SKIP_TMP_PULL=1")
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
    local_name = export.get("localFileName")
    if local_name:
        matches = sorted(root.rglob(f"exports/{local_name}"))
        if matches:
            print(matches[-1])
            raise SystemExit

    file_path = export.get("filePath")
    if file_path:
        matches = sorted(root.rglob(f"exports/{pathlib.Path(file_path).name}"))
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
