#!/usr/bin/env bash
set -euo pipefail

THRESHOLD_PERCENT="${THRESHOLD_PERCENT:-80}"
PROJECT_PATH="${PROJECT_PATH:-millio.xcodeproj}"
SCHEME="${SCHEME:-millio}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 16}"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-.build/coverage/${SCHEME}.xcresult}"
TARGET_NAME="${TARGET_NAME:-millio.app}"

mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"

xcodebuild test \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -enableCodeCoverage YES \
  -resultBundlePath "$RESULT_BUNDLE_PATH"

rm -rf ~/Library/Developer/XCTestDevices/*/

REPORT="$(xcrun xccov view --report "$RESULT_BUNDLE_PATH")"
echo "$REPORT"

PERCENT_LINE="$(echo "$REPORT" | awk -v target="$TARGET_NAME" '$1 == target { print; found=1 } END { if (!found) exit 1 }' || true)"
if [[ -z "$PERCENT_LINE" ]]; then
  PERCENT_LINE="$(echo "$REPORT" | awk 'NF >= 2 && $2 ~ /%/ { print; exit }')"
fi

PERCENT="$(echo "$PERCENT_LINE" | awk '{ for (i=1; i<=NF; i++) if ($i ~ /%/) { gsub(/%/, "", $i); print $i; exit } }')"

python3 - <<PY
threshold = float("${THRESHOLD_PERCENT}")
percent = float("${PERCENT}")
if percent + 1e-9 < threshold:
    raise SystemExit(f"Coverage gate failed: {percent:.2f}% < {threshold:.2f}%")
print(f"Coverage gate passed: {percent:.2f}% >= {threshold:.2f}%")
PY
