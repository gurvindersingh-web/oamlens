#!/usr/bin/env bash
# Zoom Lens (zoom-lens.magnifier) - finite setup supervisor.
#
# Runs enable.sh once per invocation inside its own session/process group and
# owns the whole finite setup lifecycle:
#   - a non-blocking flock is held from acquisition until this process exits,
#     so concurrent service loads serialize and a failed run can be retried;
#   - the setup helper runs under a hard 8s deadline;
#   - on deadline or interrupt the whole setup group gets SIGTERM, a 2s grace,
#     then SIGKILL, and the supervisor stays until the group is gone and reaped;
#   - descendants left behind after a normal helper exit are terminated too;
#   - each invocation settles exactly once by writing an atomic enable.status.
# Setup output is discarded, never buffered.
#
# Exit codes: 0 = setup ok, 1 = setup failed, 2 = another run is in progress,
#             3 = deadline reached or supervisor interrupted.
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-zoom-lens"
LOCK_FILE="$STATE_DIR/enable.lock"
PID_FILE="$STATE_DIR/enable.pid"
STATUS_FILE="$STATE_DIR/enable.status"
DEADLINE_SECS=8
TERM_GRACE_TICKS=20
KILL_GRACE_TICKS=20
GROUP=""
CHILD=""

# Atomic settlement record. A failure to write it must not mask the outcome.
status_write() {
  local state="$1" code="$2" message="$3" tmp
  tmp="$(mktemp "$STATE_DIR/.status.XXXXXX" 2>/dev/null)" || return 0
  if printf 'state=%s\nexit=%s\nmessage=%s\n' "$state" "$code" "$message" >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$STATUS_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

fail() {
  status_write "failed" "$1" "$2"
  exit 1
}

group_alive() {
  [[ -n "$GROUP" ]] || return 1
  kill -0 -- "-$GROUP" 2>/dev/null
}

# TERM the whole setup group, wait out the grace period, then KILL what is
# left. Returns non-zero only if the group cannot be confirmed gone.
terminate_group() {
  [[ -n "$GROUP" ]] || return 0
  local i
  kill -TERM -- "-$GROUP" 2>/dev/null || true
  for ((i = 0; i < TERM_GRACE_TICKS; i++)); do
    group_alive || return 0
    sleep 0.1
  done
  kill -KILL -- "-$GROUP" 2>/dev/null || true
  for ((i = 0; i < KILL_GRACE_TICKS; i++)); do
    group_alive || return 0
    sleep 0.1
  done
  return 1
}

on_signal() {
  trap '' TERM INT HUP
  terminate_group || true
  if [[ -n "$CHILD" ]]; then
    wait "$CHILD" 2>/dev/null || true
  fi
  rm -f "$PID_FILE" 2>/dev/null || true
  status_write "interrupted" 3 "setup supervisor was interrupted"
  exit 3
}

mkdir -p "$STATE_DIR" 2>/dev/null || exit 1
trap on_signal TERM INT HUP

command -v flock >/dev/null 2>&1 \
  || fail 127 "flock from util-linux is required to serialize setup"
command -v setsid >/dev/null 2>&1 \
  || fail 127 "setsid from util-linux is required to supervise setup"

exec 200>>"$LOCK_FILE" 2>/dev/null || fail 1 "cannot open $LOCK_FILE"
if ! flock -n 200; then
  # The lock holder reports the shared outcome; do not clobber its status.
  exit 2
fi

: >"$PID_FILE" 2>/dev/null || fail 1 "cannot write $PID_FILE"

# The helper runs in a new session, so its own PID is the setup process-group
# ID. It reports that PID once, before exec'ing; the supervisor keeps it in
# memory and never reads the file again. setsid -w keeps $CHILD alive for
# exactly as long as the helper and forwards its exit status.
ZOOM_LENS_SUPERVISED=1 setsid -w bash -c \
  'printf "%s\n" "$$" > "$1" || exit 126; exec bash "$2"' \
  _ "$PID_FILE" "$SELF_DIR/enable.sh" </dev/null >/dev/null 2>&1 &
CHILD=$!

for ((i = 0; i < 40; i++)); do
  if [[ -s "$PID_FILE" ]]; then
    IFS= read -r GROUP <"$PID_FILE" || GROUP=""
    if [[ "$GROUP" =~ ^[0-9]+$ ]]; then
      break
    fi
    GROUP=""
  fi
  sleep 0.05
done

if [[ ! "$GROUP" =~ ^[0-9]+$ ]]; then
  kill -TERM "$CHILD" 2>/dev/null || true
  wait "$CHILD" 2>/dev/null || true
  rm -f "$PID_FILE" 2>/dev/null || true
  fail 1 "setup helper did not report its process group"
fi

deadline=$(( $(date +%s) + DEADLINE_SECS ))
timed_out=0
while kill -0 "$CHILD" 2>/dev/null; do
  if (( $(date +%s) >= deadline )); then
    timed_out=1
    break
  fi
  sleep 0.1
done

if (( timed_out )); then
  terminate_group || true
  wait "$CHILD" 2>/dev/null || true
  rm -f "$PID_FILE" 2>/dev/null || true
  status_write "timeout" 3 "setup exceeded ${DEADLINE_SECS}s and was terminated"
  exit 3
fi

wait "$CHILD" 2>/dev/null
code=$?
rm -f "$PID_FILE" 2>/dev/null || true

# A helper that exited while leaving descendants behind is not a clean run:
# terminate what is left in its group instead of abandoning it.
if group_alive; then
  if terminate_group; then
    status_write "failed" "$code" "setup left background processes; they were terminated"
  else
    status_write "failed" "$code" "setup left an unkillable process group"
  fi
  exit 1
fi

if (( code == 0 )); then
  status_write "ok" 0 "setup completed"
  exit 0
fi

status_write "failed" "$code" "enable helper exited with status $code"
exit 1
