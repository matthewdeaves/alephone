#!/usr/bin/env bash
# bench-fps.sh - interleaved frame-rate measurement of the INSTALLED Aleph One
# on a real fleet Mac (alephone#39).
#
# usage: scripts/bench-fps.sh <host-alias> [rounds=3] [seconds-per-run=40]
#
# Each round plays the Marathon 2 L00 demo film once per fps target (30, 60,
# unlimited), in that interleaved order, fullscreen (the shipped default),
# sound off, with ALEPHONE_FPS_LOG=5. The first 5 s window of every run is
# discarded as cold start. HOME points at a scratch dir under
# ~/oldmac/alephone/bench, so the player's own preferences are never read
# or written; the first run there is a first run, so the log also shows the
# GL tier this Mac gets. Claims the host through pick-bench-host.sh and
# terminates every run with the same quit, TERM, KILL escalation as smoke-dmg.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${1:?usage: $0 <host-alias> [rounds] [seconds-per-run]}"
ROUNDS="${2:-3}"
SECS="${3:-40}"

export BENCH_LOCK_CLAIM="${BENCH_LOCK_CLAIM:-alephone.bench.$$.$(date +%s)}"
"$REPO_ROOT/scripts/pick-bench-host.sh" --acquire "$HOST" "alephone #39 fps bench" >/dev/null || {
	echo "bench-fps.sh: could not claim $HOST; see scripts/pick-bench-host.sh --status" >&2
	exit 1
}
trap '"$REPO_ROOT/scripts/pick-bench-host.sh" --release "$HOST" >/dev/null 2>&1; true' EXIT

# Refuse to launch into a locked/shielded console (old-mac-build-host#88):
# the game never comes to the front there, so a "pass" would mean nothing.
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gui-precondition.sh" "$HOST" || {
	echo "UNTESTED: $HOST console is not ready for a GUI launch (gui-precondition.sh)" >&2
	exit 1
}

ssh "$HOST" bash -s -- "$ROUNDS" "$SECS" << 'REMOTE_BENCH'
# No pipefail: Tiger's /bin/bash 2.05b rejects it.
set -u
ROUNDS="$1"; SECS="$2"
APP_DIR="/Applications/Aleph One"
EXEC="$APP_DIR/Aleph One.app/Contents/MacOS/Aleph One"
DATA="$APP_DIR/Scenarios/Marathon 2"
FILM="$DATA/Demos/L00.filA"
W="$HOME/oldmac/alephone/bench"
[ -x "$EXEC" ] && [ -f "$FILM" ] || { echo "BENCH FAIL: install or demo film missing"; exit 1; }

rm -rf "$W"; mkdir -p "$W/home"
stop() {
	osascript -e 'tell application "Aleph One" to quit' >/dev/null 2>&1 || true
	for i in 1 2 3 4 5; do kill -0 "$1" 2>/dev/null || return 0; sleep 1; done
	kill "$1" 2>/dev/null || true
	for i in 1 2 3; do kill -0 "$1" 2>/dev/null || return 0; sleep 1; done
	kill -9 "$1" 2>/dev/null || true; sleep 1
	kill -0 "$1" 2>/dev/null && echo "BENCH FAIL: pid $1 survived SIGKILL" && exit 1
	return 0
}

r=1
while [ "$r" -le "$ROUNDS" ]; do
	for target in 30 60 0; do
		log="$W/r$r-t$target.log"
		# exec, so $! is the game itself: stop() used to kill only this
		# subshell and leave the game running into the next run (and into
		# the next claimant's session).
		( cd "$APP_DIR" && HOME="$W/home" ALEPHONE_FPS_LOG=5 ALEPHONE_FPS_TARGET=$target \
			exec "$EXEC" -s --no-chooser -Q "$DATA" "$FILM" > "$log" 2>&1 < /dev/null ) &
		pid=$!
		sleep "$SECS"
		alive=yes; kill -0 "$pid" 2>/dev/null || alive=no
		stop "$pid"
		[ "$r$target" = "130" ] && grep -E '^(GL_RENDERER|gl-tier|fps-log: window)' "$log" | sed 's/^/  /'
		# drop the first (cold) window; report mean/min fps and worst frame
		grep '^fps-log: [0-9]' "$log" | sed 1d | awk -v r="$r" -v t="$target" -v a="$alive" '
			{ f = $2; n++; s += f; if (n == 1 || f < mn) mn = f; w = $(NF-1); if (w > mw) mw = w }
			END { if (n) printf "round %d target %-3s: mean %.1f fps, min window %.1f, worst frame %.0f ms (%d windows, alive at end: %s)\n", r, (t == 0 ? "max" : t), s / n, mn, mw, n, a
			      else printf "round %d target %-3s: NO fps windows (alive at end: %s)\n", r, (t == 0 ? "max" : t), a }'
	done
	r=$((r + 1))
done
rm -rf "$W"
REMOTE_BENCH
