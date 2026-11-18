#!/usr/bin/env bash
# Boot Twilight on an iOS 27 simulator when that runtime is installed.
# A runner without iOS 27 skips the check. bootstatus -b is not used: on this
# runner it waits on SpringBoard until the job is killed.
set -euo pipefail

runtime_id="$(python3 - << 'PY'
import json
import subprocess

raw = subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"])
data = json.loads(raw)
chosen = ""
for runtime in data.get("runtimes", []):
    if not runtime.get("isAvailable", False):
        continue
    name = runtime.get("name", "")
    version = str(runtime.get("version", ""))
    identifier = runtime.get("identifier", "")
    platform = runtime.get("platform", "")
    is_ios = (
        platform == "iOS"
        or name.startswith("iOS")
        or ".iOS." in identifier
        or "iOS-" in identifier
    )
    is_27 = (
        version.startswith("27")
        or name.startswith("iOS 27")
        or "iOS-27" in identifier
    )
    if is_ios and is_27:
        chosen = identifier
        break
print(chosen if chosen else "NO_IOS_27")
PY
)"

if [ "$runtime_id" = "NO_IOS_27" ]; then
  echo "No iOS 27 simulator runtime is installed on this runner."
  echo "The launch check is skipped. The iPhone and visionOS jobs are unaffected."
  echo "Installed runtimes:"
  xcrun simctl list runtimes
  exit 0
fi

echo "Using iOS 27 runtime $runtime_id"
devicetype="$(python3 - << 'PY'
import json
import subprocess

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "-j"]))
chosen = ""
for device in data.get("devicetypes", []):
    name = device.get("name", "")
    if name.startswith("iPhone"):
        chosen = device["identifier"]
        if "iPhone 16" in name or "iPhone 17" in name:
            break
if not chosen:
    raise SystemExit("No iPhone simulator device type is installed")
print(chosen)
PY
)"

udid="$(xcrun simctl create "Twilight iOS 27 Launch" "$devicetype" "$runtime_id")"
xcrun simctl boot "$udid" || true
python3 - "$udid" << 'PY'
import subprocess
import sys
import time

udid = sys.argv[1]
for _ in range(36):
    listed = subprocess.run(
        ["xcrun", "simctl", "list", "devices"],
        capture_output=True,
        text=True,
    ).stdout
    for line in listed.splitlines():
        if udid in line and "(Booted)" in line:
            sys.exit(0)
    time.sleep(5)
sys.exit("simulator %s was not Booted after 3 minutes" % udid)
PY

derived="${RUNNER_TEMP:-/tmp}/twilight-ios27"
xcodebuild -project Moonlight.xcodeproj -scheme Moonlight -configuration Debug \
  -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath "$derived" \
  build
app="$(find "$derived/Build/Products" -type d -name 'Moonlight.app' | head -1)"
if [ -z "$app" ]; then
  echo "Moonlight.app was not produced for the iOS 27 simulator."
  exit 1
fi
xcrun simctl install "$udid" "$app"
reports="${HOME}/Library/Logs/DiagnosticReports"
before="$(mktemp)"
find "$reports" \( -name '*.ips' -o -name '*.crash' \) 2>/dev/null | sort > "$before" || true
set +e
launch_out="$(xcrun simctl launch "$udid" io.github.neguete10.twilight.ios 2>&1)"
launch_status=$?
set -e
echo "simctl launch ($launch_status): $launch_out"
if [ "$launch_status" -ne 0 ]; then
  echo "simctl launch failed. iOS 27 exits here when the app has no scene lifecycle."
  exit 1
fi
pid="${launch_out##* }"
sleep 3
alive=0
if kill -0 "$pid" 2>/dev/null; then
  alive=1
elif xcrun simctl spawn "$udid" launchctl print "pid/$pid" >/dev/null 2>&1; then
  alive=1
fi
after="$(mktemp)"
find "$reports" \( -name '*.ips' -o -name '*.crash' \) 2>/dev/null | sort > "$after" || true
new_reports="$(comm -13 "$before" "$after" || true)"
relevant="$(printf '%s\n' "$new_reports" | grep -E 'Moonlight|Twilight|twilight' || true)"
if [ -n "$relevant" ]; then
  echo "New Twilight crash reports after launch:"
  echo "$relevant"
  printf '%s\n' "$relevant" | while IFS= read -r report; do
    [ -n "$report" ] && echo "----- $report -----" && head -c 4000 "$report" || true
    echo
  done
fi
if [ "$alive" -ne 1 ]; then
  echo "Twilight exited within 3 seconds of launch on the iOS 27 simulator (pid $pid)."
  echo "iOS 27 enforces the UIScene lifecycle. An early EXC_BREAKPOINT in UIApplicationMain means the scene manifest or SceneDelegate did not keep the process up."
  exit 1
fi
if [ -n "$relevant" ]; then
  echo "Twilight was still running, but a new crash report appeared during launch."
  exit 1
fi
echo "Twilight was still running 3 seconds after launch on iOS 27."
