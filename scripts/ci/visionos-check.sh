#!/usr/bin/env bash
# The Moonlight scheme is an iPhone and iPad app (Designed for iPad on Vision Pro).
# This check builds it for the visionOS Simulator when that destination exists,
# and explains the skip when it does not. The caller marks the job non-blocking.
set -euo pipefail

if [ "${VISIONOS_PLATFORM_READY:-0}" != "1" ]; then
  echo "visionOS platform download did not succeed."
  echo "The Moonlight scheme stays an iPhone and iPad app. This job does not affect those builds."
  exit 0
fi

dest_log="$(mktemp)"
xcodebuild -project Moonlight.xcodeproj -scheme Moonlight -showdestinations >"$dest_log" 2>&1
set +e
python3 - "$dest_log" << 'PY'
import sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
available = text.split("Available destinations", 1)[-1].split("Ineligible destinations", 1)[0]
sys.exit(0 if "visionOS Simulator" in available else 1)
PY
has_destination=$?
set -e
if [ "$has_destination" -ne 0 ]; then
  echo "The Moonlight scheme has no visionOS Simulator destination, so it was not built as a native visionOS app."
  echo "TARGETED_DEVICE_FAMILY is 1,2 and SDKROOT is iphoneos. On Apple Vision Pro this binary runs as the existing iPad app."
  echo "A native visionOS build needs its own target before this destination exists."
  echo "Destinations from xcodebuild:"
  cat "$dest_log"
  exit 0
fi

build_log="$(mktemp)"
set +e
xcodebuild -project Moonlight.xcodeproj -scheme Moonlight -configuration Debug \
  -destination "generic/platform=visionOS Simulator" build >"$build_log" 2>&1
build_status=$?
set -e
cat "$build_log"
if [ "$build_status" -eq 0 ]; then
  exit 0
fi
if grep -E -q "Unable to find a destination|supported destinations|not compatible with visionOS|supported platforms" "$build_log"; then
  echo "The Moonlight scheme cannot target the visionOS Simulator without a project change."
  echo "It remains the iPhone and iPad app, which runs on Vision Pro as Designed for iPad."
  exit 0
fi
echo "The visionOS Simulator build of the Moonlight scheme failed. See the log above for what a native build would break."
echo "This job does not fail the iPhone build."
exit "$build_status"
