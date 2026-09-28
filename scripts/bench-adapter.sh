# bench-adapter.sh -- alephone's port adapter for bench-evidence.sh
# (build-host#104, old-mac-build-host/docs/bench-evidence.md). Port-owned:
# never synced from old-mac-build-host, never edited from there.
#
# Reuses the same launch shape as bench-fps.sh (alephone#39/#42): fullscreen,
# sound off, Marathon 2 L00 demo film, -l/--replay-directory so a headless
# launch doesn't lose OS focus and freeze world ticks (alephone#42).
#
# Tunables (env, set by the caller before invoking bench-evidence.sh):
#   ALEPHONE_BENCH_TARGET   fps target to request (ALEPHONE_FPS_TARGET), default 60
#   ALEPHONE_BENCH_LOG_SECS ALEPHONE_FPS_LOG window seconds, default 2 (short,
#                           so bench_liveness's two samples 3s apart straddle
#                           at least one completed window)
#   ALEPHONE_BENCH_SECS     how long bench_launch itself runs the game for
#                           before returning, default 12
#   ALEPHONE_BENCH_FILM     demo film basename under Marathon 2/Demos, default
#                           L00 (light scene). alephone#45 heavy-scene protocol
#                           (same film alephone#42 used) sets this to L05.
#   ALEPHONE_BENCH_QUIT_GRACE  seconds bench_launch leaves the game running
#                           after it returns, before asking it to quit -- must
#                           outlast bench-evidence.sh's own post-return ssh
#                           round trips (host info, hashing, frame capture)
#                           plus its two 3s-apart liveness samples, or those
#                           land on an already-quitting process. Default 20
#                           (alephone#45: 6 raced this on imac-g5).
#   ALEPHONE_BENCH_FORCE_CLASSIC  set to 1 to export ALEPHONE_FORCE_CLASSIC_GL=1
#                           into the remote launch, forcing the classic
#                           fixed-function renderer instead of the shader one
#                           (screen.cpp's existing diagnostic override,
#                           BUGFIXES.md alephone#16 -- not a code change, a
#                           preference toggle for telling a slow *engine*
#                           renderer path from a slow *emulator* GL path on a
#                           new host). Default unset (shader, whichever the
#                           GPU/driver would pick unforced). On qemu-tiger3d
#                           defaults to 1, matching its installed VM profile.
#                           Set 0 explicitly to reproduce the shader fault.
#
# qemu-tiger3d (alephone#46): the QemuMac VM host is just another ssh alias
# to _ao_sh above -- the classic GL default is VM-specific. It is slower and
# less consistent than real hardware (emulated G4 7400 + Radeon 9700 PRO,
# Tiger 10.4, fps follows workstation load), so bump ALEPHONE_BENCH_SECS and
# ALEPHONE_BENCH_QUIT_GRACE well above their defaults when targeting it, the
# same way the Quake ports' bench.sh gives this host a 300s timeout instead
# of their usual per-class values. Bring the VM up first with
# `scripts/shared.sh qemu-vm.sh up`, or let the shared picker boot it on claim.
#
# alephone#43 (build-host#105 pin migration): bench-evidence.sh now runs from
# old-mac-build-host's pinned-revision cache (~/.cache/retro-shared/<sha>/),
# not from this repo's scripts/ next to this file, so its own
# `$SELF_DIR/bench-adapter.sh` default can no longer find this file. Always
# invoke it as:
#   BENCH_ADAPTER="$REPO_ROOT/scripts/bench-adapter.sh" scripts/shared.sh bench-evidence.sh <host> <round> ...

# shellcheck disable=SC2034  # read by bench-evidence.sh after it sources this file
PORT=alephone
# Absolute, not $HOME-relative: our install is always at root /Applications
# (fleet policy), never $HOME/Applications. Needed build-host#107 upstream
# (fixed) before this was readable at all.
# shellcheck disable=SC2034  # read by bench-evidence.sh after it sources this file
INSTALL_BIN='/Applications/Aleph One/Aleph One.app/Contents/MacOS/Aleph One'

_ao_paths() {
	local app_dir="/Applications/Aleph One"
	AO_EXEC="$app_dir/Aleph One.app/Contents/MacOS/Aleph One"
	AO_DATA="$app_dir/Scenarios/Marathon 2"
	AO_DEMOS="$AO_DATA/Demos"
	AO_FILM="$AO_DEMOS/${ALEPHONE_BENCH_FILM:-L00}.filA"
	AO_APP_DIR="$app_dir"
}

_ao_run_home() { echo '$HOME/oldmac/alephone/bench-evidence'; }
_ao_log_path() { echo '$HOME/oldmac/alephone/bench-evidence/game.log'; }

# Runs CMD (a string) on $1=host: locally (workstation) or over ssh.
_ao_sh() {
	local host="$1" cmd="$2"
	if [ "$host" = workstation ]; then
		bash -c "$cmd"
	else
		ssh -o BatchMode=yes -o ConnectTimeout=15 "$host" "$cmd"
	fi
}

# Blocks for the whole bench window itself (like quake3's safebench.sh), then
# leaves the game running a further grace period so bench-evidence.sh's own
# post-return work (host-info/hash ssh round trips, frame captures, then two
# liveness pings 3s apart) samples a genuinely still-live, still-ticking
# process, and schedules its own stop -- detached, on the remote side -- so
# nothing leaks regardless of what the caller does next.
#
# alephone#45: the original 6s grace raced that post-return work on imac-g5
# (a real Leopard PowerPC host, not a fast dev box) -- ssh round trips for
# sysctl/sw_vers/hashing alone routinely ate 3-8s before the first liveness
# sample, so the quit (or its AppleScript Apple-Event delivery pausing the
# game's own focus) had often already fired by sampling time: measured as
# both "liveness did not advance" (ticks frozen) and "frames byte-identical"
# on the same runs, even though fps-log showed real, continuously-advancing
# gameplay the whole time (confirmed with a 30s direct, unwrapped run).
# 20s leaves comfortable headroom for that overhead on this class of host.
bench_launch() {
	local host="$1" round="$2" workdir="$3"
	_ao_paths
	local target="${ALEPHONE_BENCH_TARGET:-60}"
	local log_secs="${ALEPHONE_BENCH_LOG_SECS:-2}"
	local secs="${ALEPHONE_BENCH_SECS:-12}"
	local quit_grace="${ALEPHONE_BENCH_QUIT_GRACE:-20}"
	local force_classic=""
	local classic_default=0
	[ "$host" = qemu-tiger3d ] && classic_default=1
	[ "${ALEPHONE_BENCH_FORCE_CLASSIC:-$classic_default}" = 1 ] && force_classic="ALEPHONE_FORCE_CLASSIC_GL=1 "

	# build-host#147 / alephone#53: the game is started by the shared
	# launch-game.sh (refuses if any game already runs on the host; its guest
	# watchdog TERMs the game after --max-secs, which replaces the old detached
	# quit subshell, so nothing leaks even if the caller dies). The launcher
	# script execs the game, so the pid reported is the game itself.
	local rhome; rhome="$(_ao_sh "$host" 'echo $HOME')"
	local remote_dir="$rhome/oldmac/alephone/bench-evidence"
	local remote_log="$remote_dir/game.log"
	local launcher
	launcher="$(dirname "${BASH_SOURCE[0]}")/shared.sh"

	if ! _ao_sh "$host" "[ -x '$AO_EXEC' ] && [ -f '$AO_FILM' ]"; then
		echo "BENCH FAIL: install or demo film missing" > "$workdir/log.txt"
		echo "EXIT=127"; echo "PID="
		return 0
	fi
	_ao_sh "$host" "rm -rf '$remote_dir'; mkdir -p '$remote_dir/home' && cat > '$remote_dir/launch.sh'" <<EOL
cd '$AO_APP_DIR' && HOME='$remote_dir/home' ALEPHONE_FPS_LOG=$log_secs ALEPHONE_FPS_TARGET=$target ${force_classic}exec '$AO_EXEC' -s --no-chooser -Q -l '$AO_DEMOS' '$AO_DATA' '$AO_FILM' > '$remote_log' 2>&1 < /dev/null
EOL
	local launch_out pid="" alive=no exitc=1
	if launch_out="$("$launcher" launch-game.sh "$host" alephone --max-secs $((secs + quit_grace + 5)) -- sh "$remote_dir/launch.sh" 2>"$workdir/launch-game.err")"; then
		pid="$(printf '%s\n' "$launch_out" | awk '/^PID /{print $2}')"
		sleep "$secs"
		if _ao_sh "$host" "kill -0 $pid 2>/dev/null"; then alive=yes; exitc=0; fi
	else
		exitc=$?
	fi
	_ao_sh "$host" "cat '$remote_log' 2>/dev/null" > "$workdir/log.txt" || true
	[ -s "$workdir/launch-game.err" ] && cat "$workdir/launch-game.err" >> "$workdir/log.txt"

	grep '^fps-log: [0-9]' "$workdir/log.txt" 2>/dev/null | sed 1d | awk '{print $2}' > "$workdir/stats.txt"
	echo fps > "$workdir/stats.unit"

	# build-host#135/alephone#50: $workdir is already bench-evidence.sh's own
	# bundle dir, never this repo's tree, so a peer-run bench here never left
	# uncommitted output -- but mirror the raw log into BENCH_OUT_DIR (the
	# bundle's port-out/) too when set, so the bundle carries a self-contained
	# copy instead of port-out/ being empty for this adapter.
	if [ -n "${BENCH_OUT_DIR:-}" ]; then
		cp "$workdir/log.txt" "$BENCH_OUT_DIR/round-$round.log" 2>/dev/null || true
	fi

	echo "EXIT=${exitc:-unknown}"
	[ "$alive" = yes ] && echo "PID=$pid" || echo "PID="
}

# Sums the "ticks N" delta field across every completed fps-log window seen
# so far (alephone#42: a frozen/paused scene keeps drawing at a steady fps
# with 0 world ticks, so fps alone can't tell live from paused -- this can).
# Older installs without the ticks field (pre-21f3761f) never match the awk
# condition, so this reads back empty on them: still exercises the check,
# just with no signal on those installs, never a false pass.
bench_liveness() {
	local host="$1"
	local log_path; log_path="$(_ao_log_path)"
	_ao_sh "$host" "awk '/^fps-log: [0-9]/ && \$(NF-1) == \"ticks\" { t += \$NF } END { if (t != \"\") print t+0 }' \"$log_path\" 2>/dev/null"
}

# Reads back the one-time window-open line. renderer=/resolution= are on
# every install (manager ask, old-mac-build-host#109 comments: report
# resolution so a fullscreen/WxH mismatch fails --requested, the halflife
# bug). fps_target= only appears on installs with 3d35e96f (screen.cpp
# printing get_fps_target(), so an ALEPHONE_FPS_TARGET override shows up
# here as the run's actual effective target, not just the raw preference
# value the older gl-tier line reports) -- absent, not fabricated, on an
# older install.
bench_effective_config() {
	local host="$1"
	local log_path; log_path="$(_ao_log_path)"
	local line; line="$(_ao_sh "$host" "grep -m1 '^fps-log: window' \"$log_path\" 2>/dev/null")"
	printf '%s\n' "$line" | sed -n 's/^fps-log: window [0-9]*s, renderer \([a-z]*\), \([0-9]*x[0-9]*\).*/renderer=\1\nresolution=\2/p'
	printf '%s\n' "$line" | sed -n 's/.*fps_target \([0-9]*\)$/fps_target=\1/p'
	_ao_sh "$host" "grep -m1 '^GL_RENDERER:' \"$log_path\" 2>/dev/null" | sed -n 's/^GL_RENDERER: /gl_renderer=/p'
}
