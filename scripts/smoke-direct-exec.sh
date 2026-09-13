#!/usr/bin/env bash
# smoke-direct-exec.sh - Direct-exec launch smoke test on a real fleet machine,
# for hosts where LaunchServices-over-SSH (smoke-dmg.sh) is not trustworthy:
# the documented Tiger/Panther "open does nothing over ssh" caveat, or a real
# ssh-user/console-user mismatch (measured on g5-panther: ssh user
# "powermacg5" != console user "powermac", so `open` silently no-ops there
# regardless of app health -- see BUGFIXES.md and alephone#37/#32).
#
# alephone#32 (2026-09-13, evening): a hand-rolled version of this same
# pattern, run ad hoc over ssh across several smoke passes, left TWO real
# Aleph One processes running on quicksilver -- `kill $PID` (bare SIGTERM)
# doesn't reliably terminate this engine under direct exec (unclear whether
# it's ignored, deferred, or the process was already past the point my
# `sleep 2` checked). A peer's own benchmark on that shared host measured a
# real FPS hit from the contamination. This script exists so that mistake
# has nowhere to recur: it escalates (graceful quit -> SIGTERM -> SIGKILL)
# and VERIFIES nothing survives before it exits, every time, unconditionally
# -- not only on the success path.
#
# usage: scripts/smoke-direct-exec.sh <host-alias> [seconds-to-observe]
# effect: launches Aleph One directly (no LaunchServices), observes it,
#         guarantees termination, reports PASS/FAIL for the observation.

set -euo pipefail

HOST="${1:?usage: $0 <host-alias> [seconds]}"
OBSERVE_SECS="${2:-15}"

echo "[smoke-direct] $HOST: launching \"Aleph One\" via direct exec (bypassing LaunchServices)..."

ssh "$HOST" bash -s -- "$(printf '%q' "$OBSERVE_SECS")" << 'REMOTE_SMOKE'
# Not pipefail: some fleet targets (Tiger 10.4's stock /bin/bash 2.05b)
# predate it and abort the whole `set` with "invalid option name" on a bare
# `set -uo pipefail`, silently leaving -u unset too.
set -u
OBSERVE_SECS="$1"
APP_PATH="/Applications/Aleph One/Aleph One.app"
EXEC_PATH="$APP_PATH/Contents/MacOS/Aleph One"
LOG="/tmp/alephone-direct-exec-smoke.$$.log"

if [ ! -x "$EXEC_PATH" ]; then
	echo "SMOKE FAIL: $EXEC_PATH does not exist or is not executable (deploy first)"
	exit 1
fi

# All three FDs redirected on the child's own launch line -- an ssh session
# that inherits any of them keeps the whole `ssh` call from returning even
# after this script itself finishes (legacy-mac-hardware.md's own
# operational-lessons section covers this exact gotcha).
( cd "$APP_PATH/.." && "$EXEC_PATH" > "$LOG" 2>&1 < /dev/null ) &
PID=$!

sleep "$OBSERVE_SECS"

RESULT=1
if kill -0 "$PID" 2>/dev/null; then
	echo "SMOKE PASS: Aleph One is running ${OBSERVE_SECS}s after direct exec"
	RESULT=0
else
	echo "SMOKE FAIL: Aleph One is not running ${OBSERVE_SECS}s after direct exec (crashed or exited)"
fi

# Unconditional cleanup from here down -- runs on BOTH the PASS and FAIL
# path, and escalates until the process is actually gone rather than
# trusting the first signal sent. A bare `kill $PID` (SIGTERM) left two
# real copies running on quicksilver in the incident this script fixes;
# never repeat that with a single untried signal again.
if kill -0 "$PID" 2>/dev/null; then
	# Try a graceful quit first: it still registers by name even launched
	# via direct exec (confirmed via `tell application "Aleph One" to quit`
	# succeeding against a direct-exec instance during alephone#26's
	# investigation), and avoids the crash-relaunch nag a hard kill can
	# trigger on next launch. Non-fatal if it errors (e.g. AppleScript
	# support unavailable) -- the SIGTERM/SIGKILL escalation below still
	# runs regardless.
	osascript -e 'tell application "Aleph One" to quit' 2>/dev/null || true
	for i in 1 2 3 4 5; do
		kill -0 "$PID" 2>/dev/null || break
		sleep 1
	done
fi
if kill -0 "$PID" 2>/dev/null; then
	echo "SMOKE NOTE: graceful quit didn't take within 5s, sending SIGTERM"
	kill "$PID" 2>/dev/null || true
	for i in 1 2 3; do
		kill -0 "$PID" 2>/dev/null || break
		sleep 1
	done
fi
if kill -0 "$PID" 2>/dev/null; then
	echo "SMOKE NOTE: SIGTERM didn't take within 3s, sending SIGKILL"
	kill -9 "$PID" 2>/dev/null || true
	sleep 1
fi
if kill -0 "$PID" 2>/dev/null; then
	# Should be unreachable -- SIGKILL cannot be caught or ignored. Loud
	# and explicit rather than silently leaving a zombie for a peer to find.
	echo "SMOKE FAIL: pid $PID SURVIVED SIGKILL -- needs a human to look" >&2
	RESULT=1
else
	echo "[smoke-direct] confirmed terminated: pid $PID is gone"
fi

tail -5 "$LOG" 2>/dev/null | sed 's/^/[smoke-direct] log: /' || true
rm -f "$LOG"

exit "$RESULT"
REMOTE_SMOKE
