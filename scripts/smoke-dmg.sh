#!/usr/bin/env bash
# smoke-dmg.sh - Finder-equivalent launch smoke test on a real fleet machine.
# Uses LaunchServices `open`, not a direct binary exec, so it catches the
# Gatekeeper/quarantine/codesign/Info.plist failures a CLI exec would miss
# (alephone#5). Run after scripts/deploy-dmg.sh has installed the app.
# usage: scripts/smoke-dmg.sh <host-alias> "<App Name>" [seconds-to-observe]
#
# CAVEAT measured 2026-08-28: `open`-over-SSH does not launch anything at all
# on Tiger 10.4 (mini-g4, yosemite-tiger, ...) or presumably Panther 10.3 --
# confirmed with a known-good control (`open -a Chess` also launches nothing
# there, while the identical command launches Chess fine on Snow Leopard
# 10.6/mini-sl). This is a pre-launchd SSH/Aqua-session limitation on those
# OSes, not evidence of an app packaging bug -- a FAIL from this script on a
# 10.3/10.4 target does not prove the app itself is broken; a real Finder
# double-click by a human at the console is the only real proof there. On
# 10.5+ this script's result is trustworthy.

set -euo pipefail

HOST="${1:?usage: $0 <host-alias> \"<App Name>\" [seconds]}"
APP_NAME="${2:?usage: $0 <host-alias> \"<App Name>\" [seconds]}"
OBSERVE_SECS="${3:-8}"

echo "[smoke] $HOST: launching \"$APP_NAME\" via LaunchServices (open)..."

ssh "$HOST" bash -s -- "$APP_NAME" "$OBSERVE_SECS" << 'REMOTE_SMOKE'
# Not pipefail: some fleet targets (Tiger 10.4's stock /bin/bash 2.05b)
# predate it and abort the whole `set` with "invalid option name" on a bare
# `set -uo pipefail`, silently leaving -u unset too (see deploy-dmg.sh).
set -u
APP_NAME="$1"
OBSERVE_SECS="$2"
APP_PATH="$HOME/Desktop/${APP_NAME}/${APP_NAME}.app"

# No pgrep on Tiger/Panther. `ps -Awww -o command=` forces unlimited command
# width (plain `ps aux` truncates the COMMAND column even over a non-tty ssh
# pipe -- measured 2026-08-28, cut a 23-char path down to 10 and produced a
# false "not running").
proc_running() {
	ps -Awww -o command= 2>/dev/null | grep -F -- "$1" > /dev/null 2>&1
}

if [ ! -d "$APP_PATH" ]; then
	echo "SMOKE FAIL: $APP_PATH does not exist (deploy first)"
	exit 1
fi

# Quarantine check, informational: expect none for an internally-deployed app.
Q=$(xattr -p com.apple.quarantine "$APP_PATH" 2>/dev/null || true)
[ -n "$Q" ] && echo "SMOKE NOTE: quarantine attribute present: $Q"

BEFORE_LOG_TS="$(date '+%Y-%m-%d %H:%M:%S')"

# Plain `open`, not `-g`: Tiger's /usr/bin/open (10.3/10.4, still current on
# yosemite/mini-g4/quicksilver) predates the -g flag entirely and mishandles
# an unrecognized short flag by silently dropping the real path argument
# ("No such file: ~/-g") rather than erroring on the flag itself. -g would
# only avoid stealing keyboard focus, which doesn't matter for an unattended
# QA run. This is still the same LaunchServices path a Finder double-click
# takes, unlike execing the binary.
if ! open "$APP_PATH" 2>/tmp/smoke-open.err; then
	echo "SMOKE FAIL: LaunchServices \`open\` itself failed:"
	cat /tmp/smoke-open.err
	exit 1
fi

sleep "$OBSERVE_SECS"

EXEC_NAME="$(defaults read "$APP_PATH/Contents/Info" CFBundleExecutable 2>/dev/null || basename "$APP_NAME")"
EXEC_PATH="$APP_PATH/Contents/MacOS/$EXEC_NAME"
if proc_running "$EXEC_PATH"; then
	echo "SMOKE PASS: $APP_NAME is running ${OBSERVE_SECS}s after LaunchServices open"
	RESULT=0
else
	echo "SMOKE FAIL: $APP_NAME is not running ${OBSERVE_SECS}s after LaunchServices open (bounced-and-quit, or blocked)"
	RESULT=1
fi

# Surface anything LaunchServices/Gatekeeper logged for this launch attempt,
# in case of failure. `log show` is 10.12+ only; older targets just skip this.
log show --predicate 'process == "Gatekeeper" OR process == "syspolicyd" OR process == "launchservicesd"' \
	--start "$BEFORE_LOG_TS" --style compact 2>/dev/null | tail -20 || true

# Per fleet rule: never leave a game running after capturing what we launched
# it for. Only attempt a quit if something is actually running: AppleScript's
# `tell application X` LAUNCHES X first if it isn't already running (a classic
# gotcha), so calling it unconditionally can itself spawn a new, unwanted
# instance and then hang waiting on it -- measured 2026-08-28 on mini-sl.
# CFBundleExecutable ("Classic Marathon") can also differ from the display
# name we were called with ("Marathon"), which is a second way name-based
# `tell application` addressing goes wrong. A signal-based kill (even SIGTERM,
# let alone -9) makes macOS log a hard-kill/crash and nag with a
# crash-relaunch dialog on the app's next launch, so still prefer the
# graceful quit -- just gated on the process actually existing first.
if proc_running "$EXEC_PATH"; then
	osascript -e "tell application \"$EXEC_NAME\" to quit" 2>/dev/null || true
	for i in 1 2 3 4 5; do
		proc_running "$EXEC_PATH" || break
		sleep 1
	done
	if proc_running "$EXEC_PATH"; then
		echo "SMOKE NOTE: graceful quit didn't take within 5s, falling back to SIGTERM"
		kill $(ps -Awww -o pid=,command= 2>/dev/null | grep -F -- "$EXEC_PATH" | awk '{print $1}') 2>/dev/null || true
	fi
fi

exit "$RESULT"
REMOTE_SMOKE
