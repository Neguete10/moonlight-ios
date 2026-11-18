#!/usr/bin/env bash
# Capture the Twilight shell on an iPhone and an iPad simulator.
# iPhone frameshots stay portrait in simctl; rotate those so the header is on top.
set -euo pipefail

workspace="${GITHUB_WORKSPACE:-$(pwd)}"
out="$workspace/ui-screenshots"
mkdir -p "$out"

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
    print("NO_IOS_RUNTIME")
    sys.exit(0)
ios.sort(key=lambda r: [int(p) if p.isdigit() else 0 for p in str(r.get("version", "0")).split(".")])
chosen = ios[-1]
open("/tmp/twilight-runtime-id", "w").write(chosen["identifier"])
print(chosen["identifier"], chosen.get("version"))
PY
if [ ! -s /tmp/twilight-runtime-id ]; then
  echo "No iOS simulator runtime is installed, so UI screenshots were not captured."
  exit 1
fi
runtime_id="$(cat /tmp/twilight-runtime-id)"

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
    return None

iphone = pick(["iPhone 17 Pro"], ["iPhone 17", "iPhone 16 Pro", "iPhone 16", "iPhone"])
ipad = pick(
    ["iPad Pro 13-inch (M5)", "iPad Pro 13-inch (M4)"],
    ["iPad Pro 13", "iPad Pro 11", "iPad"],
)
if not iphone or not ipad:
    sys.exit("Could not find an iPhone and iPad simulator device type")
open("/tmp/twilight-iphone-type", "w").write(iphone)
open("/tmp/twilight-ipad-type", "w").write(ipad)
print(iphone)
print(ipad)
PY

build_app() {
  local src="$1"
  local dd="$2"
  local appfile="$3"
  if ! xcodebuild -project "$src/Moonlight.xcodeproj" -scheme Moonlight -configuration Debug \
    -sdk iphonesimulator -derivedDataPath "$dd" build >"$dd-build.log" 2>&1; then
    echo "xcodebuild failed for $src"
    tail -n 80 "$dd-build.log"
    exit 1
  fi
  find "$dd/Build/Products" -name Moonlight.app -path '*iphonesimulator*' | head -1 > "$appfile" || true
}

echo "Building this commit for screenshots at $(date -u +%H:%M:%S)"
build_app "$workspace" /tmp/dd-after /tmp/twilight-after-app
after_app="$(cat /tmp/twilight-after-app)"
echo "App: $after_app"
test -d "$after_app"

boot_device() {
  local name="$1"
  local type="$2"
  local udid
  udid="$(xcrun simctl create "$name" "$type" "$runtime_id")"
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
  printf '%s' "$udid" > /tmp/twilight-booted-udid
}

install_app() {
  local udid="$1"
  local app="$2"
  xcrun simctl terminate "$udid" io.github.neguete10.twilight.ios || true
  xcrun simctl install "$udid" "$app"
}

shot() {
  local udid="$1"
  local appearance="$2"
  local mode="$3"
  local file="$4"
  xcrun simctl ui "$udid" appearance "$appearance" || true
  xcrun simctl terminate "$udid" io.github.neguete10.twilight.ios || true
  if [ -n "$mode" ]; then
    SIMCTL_CHILD_TWILIGHT_SCREENSHOT="$mode" xcrun simctl launch "$udid" io.github.neguete10.twilight.ios
  else
    xcrun simctl launch "$udid" io.github.neguete10.twilight.ios
  fi
  sleep 4
  xcrun simctl io "$udid" screenshot "$file"
  echo "Wrote $file"
}

png_size() {
  python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(); w,h=struct.unpack(">II", d[16:24]); print("%d %d"%(w,h))' "$1"
}

upright_iphone() {
  local file="$1"
  local size w h
  size="$(png_size "$file")"
  w="${size%% *}"
  h="${size##* }"
  echo "$file captured ${w}x${h}"
  if [ "$h" -gt "$w" ]; then
    sips -r 270 "$file" >/dev/null
    size="$(png_size "$file")"
    w="${size%% *}"
    h="${size##* }"
    echo "$file rotated to ${w}x${h}"
  fi
  if [ "$w" -le "$h" ]; then
    echo "$file is still not landscape (${w}x${h})"
    exit 1
  fi
}

boot_device "Twilight iPhone" "$(cat /tmp/twilight-iphone-type)"
iphone="$(cat /tmp/twilight-booted-udid)"
install_app "$iphone" "$after_app"
for mode in empty library hosts hostsheet settings resolution pairing addhost unpaired loading video stream returnstream; do
  shot "$iphone" dark "$mode" "$out/after-iphone-${mode}-landscape-dark.png"
  upright_iphone "$out/after-iphone-${mode}-landscape-dark.png"
done
shot "$iphone" light library "$out/after-iphone-library-landscape-light.png"
shot "$iphone" light settings "$out/after-iphone-settings-landscape-light.png"
upright_iphone "$out/after-iphone-library-landscape-light.png"
upright_iphone "$out/after-iphone-settings-landscape-light.png"
xcrun simctl shutdown "$iphone" || true

boot_device "Twilight iPad" "$(cat /tmp/twilight-ipad-type)"
ipad="$(cat /tmp/twilight-booted-udid)"
install_app "$ipad" "$after_app"
for mode in empty library hostsheet settings video stream; do
  shot "$ipad" dark "$mode" "$out/after-ipad-${mode}-portrait-dark.png"
done
xcrun simctl shutdown "$ipad" || true
