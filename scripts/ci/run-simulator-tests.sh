#!/usr/bin/env bash
# Unit and UI tests on one iPhone simulator and the layout UI tests on iPad.
# TEST_RUNNER_* must be exported into xcodebuild's environment. The same
# tokens after the xcodebuild command are build settings and never reach the
# test process. Xcode strips the TEST_RUNNER_ prefix before the test sees them.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=with-timeout.sh
source "$script_dir/with-timeout.sh"

defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false

python3 - << 'PY'
import json
import subprocess
import sys

runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))
ios = [
    r for r in runtimes.get("runtimes", [])
    if r.get("isAvailable") and str(r.get("platform")) == "iOS"
]
if not ios:
    sys.exit("No iOS simulator runtime is installed")
ios.sort(key=lambda r: [int(p) if p.isdigit() else 0 for p in str(r.get("version", "0")).split(".")])
chosen = ios[-1]
open("/tmp/twilight-test-runtime", "w").write(chosen["identifier"])
print(chosen["identifier"], chosen.get("version"))
PY
runtime_id="$(cat /tmp/twilight-test-runtime)"

python3 - "$runtime_id" << 'PY'
import json
import subprocess
import sys

types = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "-j"]))
names = [d.get("name", "") for d in types.get("devicetypes", [])]

def pick(exact, prefixes):
    for name in exact:
        if name in names:
            return name
    for prefix in prefixes:
        for name in names:
            if name.startswith(prefix):
                return name
    return ""

iphone = pick(["iPhone 17 Pro"], ["iPhone 17", "iPhone 16 Pro", "iPhone 16", "iPhone"])
large = pick(
    ["iPhone 17 Pro Max", "iPhone 16 Pro Max"],
    ["iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone Air"],
)
if large == iphone:
    large = ""
ipad = pick(
    ["iPad Pro 13-inch (M5)", "iPad Pro 13-inch (M4)"],
    ["iPad Pro 13", "iPad Pro 11", "iPad"],
)
if not iphone:
    sys.exit("No iPhone simulator device type is installed")
open("/tmp/twilight-test-iphone", "w").write(iphone)
open("/tmp/twilight-test-large", "w").write(large)
open("/tmp/twilight-test-ipad", "w").write(ipad)
print("iphone", iphone)
print("large", large or "(none)")
print("ipad", ipad or "(none)")
PY

workspace="${GITHUB_WORKSPACE:-$(pwd)}"
derived="${RUNNER_TEMP:-/tmp}/twilight-tests"
shots="$workspace/ui-test-screenshots"
mkdir -p "$shots"
failed=0

# Kill the whole process group. simctl bootstatus and xcodebuild otherwise
# wait forever when a simulator never finishes booting.
run_with_timeout() {
  local seconds="$1"
  shift
  python3 - "$seconds" "$@" << 'PY'
import os
import signal
import subprocess
import sys

seconds = int(sys.argv[1])
cmd = sys.argv[2:]
for arg in cmd:
    if arg.startswith("TEST_RUNNER_"):
        print("refusing xcodebuild argument %s" % arg, flush=True)
        print("Put TEST_RUNNER_* in the environment of xcodebuild.", flush=True)
        sys.exit(1)
env = os.environ.copy()
if not env.get("TEST_RUNNER_TWILIGHT_SCREENSHOT_DIR"):
    print("TEST_RUNNER_TWILIGHT_SCREENSHOT_DIR is not in the environment", flush=True)
    sys.exit(1)
for key in sorted(env):
    if key.startswith("TEST_RUNNER_"):
        print("env %s is set" % key, flush=True)
proc = subprocess.Popen(cmd, start_new_session=True, env=env)
try:
    code = proc.wait(timeout=seconds)
except subprocess.TimeoutExpired:
    print("Timed out after %ss: %s" % (seconds, " ".join(cmd)), flush=True)
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    proc.wait()
    sys.exit(124)
sys.exit(code)
PY
}

run_one() {
  local label="$1"
  local devicetype="$2"
  local family="$3"
  shift 3
  if [ -z "$devicetype" ]; then
    echo "Skipping $label: no simulator device type"
    return 0
  fi
  local udid
  udid="$(run_deadline 60 xcrun simctl create "Twilight $label" "$devicetype" "$runtime_id")"
  udid="$(printf '%s' "$udid" | tr -d '[:space:]')"
  echo "Testing $label ($family) on $udid"
  local shotdir="$shots/$label"
  mkdir -p "$shotdir"
  export TEST_RUNNER_TWILIGHT_SCREENSHOT_DIR="$shotdir"
  if [ "$family" = "iphone" ]; then
    export TEST_RUNNER_TWILIGHT_EXPECT_LANDSCAPE=1
  else
    unset TEST_RUNNER_TWILIGHT_EXPECT_LANDSCAPE || true
  fi
  local pref_dir="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Preferences"
  mkdir -p "$pref_dir"
  defaults write "$pref_dir/com.apple.keyboard.preferences" DidShowContinuousPathIntroduction -bool true
  run_deadline 90 xcrun simctl boot "$udid" || true
  python3 - "$udid" << 'PY'
import subprocess
import sys

udid = sys.argv[1]
try:
    subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=120)
except subprocess.TimeoutExpired:
    print("bootstatus still going after 120s; xcodebuild will finish it", flush=True)
PY
  set +e
  run_with_timeout 1500 xcodebuild test \
    -project Moonlight.xcodeproj \
    -scheme Moonlight \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$derived" \
    -parallel-testing-enabled NO \
    -maximum-concurrent-test-simulator-destinations 1 \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 180 \
    -maximum-test-execution-time-allowance 240 \
    "$@" 2>&1 | tee "$shotdir/xcodebuild.log"
  local status=${PIPESTATUS[0]}
  set -e
  # The cases can all pass and the test runner still crash while exiting.
  # That makes xcodebuild return failure after "0 failures".
  if grep -q "Test Suite 'All tests' passed" "$shotdir/xcodebuild.log" \
    && ! grep -E "with [1-9][0-9]* failure" "$shotdir/xcodebuild.log"; then
    echo "All tests passed for $label (xcodebuild exit $status)"
    status=0
  fi
  xcrun simctl shutdown all || true
  xcrun simctl delete "$udid" || true
  if [ "$status" -ne 0 ]; then
    echo "Tests failed for $label (exit $status)"
    failed=1
  fi
}

# One iPhone pass runs the unit tests and the UI tests together so the job
# is not spent compiling the same app twice. The keyboard UI test stays on
# iPhone: on iPad the GitHub runner has crashed while that case was still tapping.
run_one "iphone-pro" "$(cat /tmp/twilight-test-iphone)" iphone \
  -only-testing:TwilightUnitTests -only-testing:TwilightUITests
if [ -s /tmp/twilight-test-ipad ]; then
  run_one "ipad" "$(cat /tmp/twilight-test-ipad)" ipad \
    -only-testing:TwilightUITests/TwilightUITests/testAppLaunchesAndMainFlowsFit \
    -only-testing:TwilightUITests/TwilightUITests/testHostsFitOnScreen \
    -only-testing:TwilightUITests/TwilightUITests/testStreamVideoFromPortraitAndBothLandscapes
  if [ -f "$shots/ipad/xcodebuild.log" ] && grep -q "Timed out while loading Accessibility" "$shots/ipad/xcodebuild.log"; then
    echo "iPad accessibility service did not load; retrying after a quiet shutdown"
    failed=0
    if ! grep -q "All tests passed for iphone-pro" "$shots/iphone-pro/xcodebuild.log"; then
      failed=1
    fi
    xcrun simctl shutdown all || true
    sleep 20
    run_one "ipad" "$(cat /tmp/twilight-test-ipad)" ipad \
      -only-testing:TwilightUITests/TwilightUITests/testAppLaunchesAndMainFlowsFit \
      -only-testing:TwilightUITests/TwilightUITests/testHostsFitOnScreen \
      -only-testing:TwilightUITests/TwilightUITests/testStreamVideoFromPortraitAndBothLandscapes
  fi
else
  echo "No iPad simulator device type is installed, so the iPad UI tests were not run."
fi
exit "$failed"
