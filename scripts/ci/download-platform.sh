#!/usr/bin/env bash
# Download an Xcode simulator platform. A cancelled job leaves CoreSimulator
# answering "Unable to connect", and an unbounded download can sit until the
# job limit. Retry, cap each try, and accept an SDK that is already installed.
set -euo pipefail

platform="${1:?platform name, such as iOS}"
sdk_needle="${2:?SDK name fragment, such as iphonesimulator}"

for attempt in 1 2 3 4; do
  xcrun simctl list devices >/dev/null 2>&1 || true
  set +e
  python3 - "$platform" << 'PY'
import subprocess
import sys

platform = sys.argv[1]
try:
    code = subprocess.run(
        ["xcodebuild", "-downloadPlatform", platform],
        timeout=480,
    ).returncode
except subprocess.TimeoutExpired:
    print("%s platform download exceeded 8 minutes" % platform, flush=True)
    sys.exit(1)
sys.exit(code)
PY
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    exit 0
  fi
  if xcodebuild -showsdks 2>/dev/null | grep -q "$sdk_needle"; then
    echo "$platform simulator SDK is already installed"
    exit 0
  fi
  echo "$platform platform download attempt ${attempt} failed"
  sleep $((attempt * 20))
done

echo "$platform platform download failed after 4 attempts"
exit 1
