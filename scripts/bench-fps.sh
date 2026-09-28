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
# GL tier this Mac gets. Claims the host through pick-bench-host.sh, starts each game via the shared launch-game.sh (build-host#147),
# stops every run with a quit, then launch-game.sh --stop (TERM, never KILL).
#
# host-alias also accepts qemu-tiger3d (alephone#46): the QemuMac VM on the
# workstation, an emulated G4 7400 + Radeon 9700 PRO on Tiger 10.4, reached
# over the ssh alias of the same name -- the VM uses classic GL by default to avoid Tiger
# driver software shader fallback. ALEPHONE_BENCH_FORCE_CLASSIC=0 opts out.
# The shared picker boots the VM on claim. The emulator is slower and noisier
# than real hardware and its fps follows workstation load, so pass a longer
# seconds-per-run than the 40s default (the Quake ports' equivalent bench.sh
# uses 300s for this host) and treat single qemu-tiger3d runs as informal
# unless corroborated on real hardware.
#
# -l/--replay-directory is passed with the launch (alephone#42): a game
# launched headless this way never actually gains OS keyboard focus (the
# launching shell has no controlling GUI session to hand it), so
# SDL_WINDOWEVENT_FOCUS_LOST fires and shell.cpp's pause_game() freezes world
# ticks while the renderer keeps drawing the frozen frame at a steady fps --
# looks like real playback in the fps-log, isn't. shell_options.replay_directory
# is the engine's own existing "unattended replay" gate (shell.cpp:1484): it is
# only ever checked for empty/non-empty, never scanned for files, so any
# existing directory satisfies it while the actual film to play still comes
# from the positional argument below, unchanged. This does NOT touch that
# pause-on-focus-loss behavior for a normal interactive launch (double-click),
# where it is correct and intentional.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${1:?usage: $0 <host-alias> [rounds] [seconds-per-run]}"
ROUNDS="${2:-3}"
SECS="${3:-40}"

# workstation is this machine itself (arm64 Apple Silicon), same as
# pick-bench-host.sh's own LOCAL_ALIASES: no sshd there, ssh-to-self would
# need a hostkey dance against a machine already trusted implicitly, so it
# is claimed the same way but launched with a local shell instead of ssh.
LOCAL_ALIASES="${LOCAL_ALIASES:-workstation}"
is_local_host() {
	case " $LOCAL_ALIASES " in
		*" $1 "*) return 0 ;;
		*)        return 1 ;;
	esac
}

if [ "${RETRO_BENCH_LOCK:-}" != "$HOST" ]; then
    exec "$REPO_ROOT/scripts/shared.sh" pick-bench-host.sh --run "$HOST" alephone-fps -- "$0" "$@"
fi

# Refuse to launch into a locked/shielded console (old-mac-build-host#88):
# the game never comes to the front there, so a "pass" would mean nothing.
if is_local_host "$HOST"; then
	"$REPO_ROOT/scripts/shared.sh" gui-precondition.sh || {
		echo "UNTESTED: $HOST console is not ready for a GUI launch (gui-precondition.sh)" >&2
		exit 1
	}
else
	"$REPO_ROOT/scripts/shared.sh" gui-precondition.sh "$HOST" || {
		echo "UNTESTED: $HOST console is not ready for a GUI launch (gui-precondition.sh)" >&2
		exit 1
	}
fi

# build-host#147 / alephone#53: the driver (this script) runs the loop and starts
# every game through the shared launch-game.sh, which refuses if any game is
# already running on the host, arms a guest-side watchdog, and stops the game with
# TERM. Remote work is only short sh commands, so nothing here backgrounds a game
# itself.
host_sh() {
	if is_local_host "$HOST"; then bash -c "$1"
	else ssh -o BatchMode=yes -o ConnectTimeout=15 "$HOST" "$1"; fi
}
launch_game() { "$REPO_ROOT/scripts/shared.sh" launch-game.sh "$@"; }

CLASSIC_DEFAULT=0
[ "$HOST" = qemu-tiger3d ] && CLASSIC_DEFAULT=1
FORCE_CLASSIC="${ALEPHONE_BENCH_FORCE_CLASSIC:-$CLASSIC_DEFAULT}"

RHOME="$(host_sh 'echo $HOME')"
APP_DIR="/Applications/Aleph One"
EXEC="$APP_DIR/Aleph One.app/Contents/MacOS/Aleph One"
DATA="$APP_DIR/Scenarios/Marathon 2"
DEMOS="$DATA/Demos"
FILM="$DEMOS/L00.filA"
W="$RHOME/oldmac/alephone/bench"
host_sh "[ -x '$EXEC' ] && [ -f '$FILM' ]" || { echo "BENCH FAIL: install or demo film missing"; exit 1; }

host_sh "rm -rf '$W'; mkdir -p '$W/home'"
GPID=""
stop_game() {
	[ -n "$GPID" ] || return 0
	host_sh "osascript -e 'tell application \"Aleph One\" to quit' >/dev/null 2>&1 || true; for i in 1 2 3 4 5; do kill -0 $GPID 2>/dev/null || exit 0; sleep 1; done" || true
	launch_game --stop "$HOST" "$GPID" || { echo "BENCH FAIL: pid $GPID survived TERM"; exit 1; }
	GPID=""
}
trap stop_game EXIT INT TERM

r=1
while [ "$r" -le "$ROUNDS" ]; do
	for target in 30 60 0; do
		log="$W/r$r-t$target.log"
		classic=""; [ "$FORCE_CLASSIC" = 1 ] && classic="ALEPHONE_FORCE_CLASSIC_GL=1 "
		# The launcher execs the game, so the pid launch-game.sh reports is
		# the game itself and --stop terminates the game, not a subshell.
		host_sh "cat > '$W/launch.sh'" <<EOF
cd '$APP_DIR' && HOME='$W/home' ALEPHONE_FPS_LOG=5 ALEPHONE_FPS_TARGET=$target ${classic}exec '$EXEC' -s --no-chooser -Q -l '$DEMOS' '$DATA' '$FILM' > '$log' 2>&1 < /dev/null
EOF
		out="$(launch_game "$HOST" alephone --max-secs $((SECS + 60)) -- sh "$W/launch.sh")" || {
			echo "BENCH FAIL: launch-game.sh refused or failed for round $r target $target"; exit 1; }
		GPID="$(printf '%s\n' "$out" | awk '/^PID /{print $2}')"
		sleep "$SECS"
		alive=yes; host_sh "kill -0 $GPID 2>/dev/null" || alive=no
		stop_game
		hostlog="$(host_sh "cat '$log'")"
		[ "$r$target" = "130" ] && printf '%s\n' "$hostlog" | grep -E '^(GL_RENDERER|gl-tier|fps-log: window)' | sed 's/^/  /'
		# drop the first (cold) window; report mean/min fps and worst frame.
		# fps-log ends ", ticks N" (alephone#42, 21f3761f) once a host's
		# installed binary has the world-tick liveness field; older
		# installs still end "... ms" with no trailing ticks token. Detect
		# by whether the line's last field is bare digits, so this parses
		# both formats correctly instead of silently misreading worst-frame
		# once any host gets the new binary.
		printf '%s\n' "$hostlog" | grep '^fps-log: [0-9]' | sed 1d | awk -v r="$r" -v t="$target" -v a="$alive" '
			{
				f = $2; n++; s += f; if (n == 1 || f < mn) mn = f
				if ($NF ~ /^[0-9]+$/ && $(NF-1) == "ticks") { w = $(NF-3); tk = $NF; have_ticks = 1; tsum += tk }
				else { w = $(NF-1) }
				if (w > mw) mw = w
			}
			END {
				frozen = (have_ticks && tsum == 0) ? " -- FROZEN (0 world ticks)" : ""
				if (n) printf "round %d target %-3s: mean %.1f fps, min window %.1f, worst frame %.0f ms%s (%d windows, alive at end: %s)\n", r, (t == 0 ? "max" : t), s / n, mn, mw, frozen, n, a
				else printf "round %d target %-3s: NO fps windows (alive at end: %s)\n", r, (t == 0 ? "max" : t), a
			}'
	done
	r=$((r + 1))
done
host_sh "rm -rf '$W'"
