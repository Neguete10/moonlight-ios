# Shared by the CI scripts. Source it; do not execute it.
# run_deadline SECONDS command...
# The command's output passes through. Exit 124 when it is still running.

run_deadline() {
  local seconds="$1"
  shift
  python3 - "$seconds" "$@" << 'PY'
import os
import signal
import subprocess
import sys

seconds = int(sys.argv[1])
cmd = sys.argv[2:]
proc = subprocess.Popen(cmd, start_new_session=True)
try:
    code = proc.wait(timeout=seconds)
except subprocess.TimeoutExpired:
    print("timed out after %ss: %s" % (seconds, " ".join(cmd)), file=sys.stderr, flush=True)
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    proc.wait()
    sys.exit(124)
sys.exit(code)
PY
}

# boot_named_simulator NAME DEVICETYPE RUNTIME
# Prints the booted UDID. Progress goes to stderr so a caller can capture the id.
# simctl create, boot, and list are capped. One retry covers a CoreSimulator
# service that answers "Unable to connect" right after the previous job.
boot_named_simulator() {
  local name="$1"
  local devicetype="$2"
  local runtime_id="$3"
  local attempt udid

  wait_until_booted() {
    python3 - "$1" << 'PY'
import os
import signal
import subprocess
import sys
import time

udid = sys.argv[1]
for i in range(24):
    proc = subprocess.Popen(
        ["xcrun", "simctl", "list", "devices"],
        start_new_session=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    try:
        listed, _ = proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        print("simctl list timed out while waiting for %s" % udid, file=sys.stderr, flush=True)
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()
        time.sleep(5)
        continue
    for line in listed.splitlines():
        if udid in line and "(Booted)" in line:
            sys.exit(0)
    if i % 3 == 0:
        print("waiting for %s (%ss)" % (udid, i * 5), file=sys.stderr, flush=True)
    time.sleep(5)
print("simulator %s was not Booted after 2 minutes" % udid, file=sys.stderr, flush=True)
sys.exit(1)
PY
  }

  for attempt in 1 2; do
    echo "Booting $name (attempt $attempt) at $(date -u +%H:%M:%S)" >&2
    xcrun simctl list devices >/dev/null 2>&1 || true
    if ! udid="$(run_deadline 60 xcrun simctl create "$name" "$devicetype" "$runtime_id")"; then
      echo "simctl create failed for $name" >&2
      sleep 10
      continue
    fi
    udid="$(printf '%s' "$udid" | tr -d '[:space:]')"
    echo "Created $name $udid" >&2
    run_deadline 90 xcrun simctl boot "$udid" >&2 || true
    if wait_until_booted "$udid"; then
      printf '%s\n' "$udid"
      return 0
    fi
    run_deadline 30 xcrun simctl shutdown "$udid" >&2 || true
    run_deadline 30 xcrun simctl delete "$udid" >&2 || true
    sleep 10
  done
  echo "simulator $name did not boot" >&2
  return 1
}
