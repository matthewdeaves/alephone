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

PORT=alephone
# Contract (docs/bench-evidence.md) allows INSTALL_BIN to be $HOME-relative
# or absolute; bench-evidence.sh's own hash check only implements the
# $HOME-relative case ("$HOME/$INSTALL_BIN"), so with an absolute path here
# that check degrades to NOTCHECKED rather than comparing the wrong file.
# Our install is always at root /Applications (fleet policy), never
# $HOME/Applications -- flagged upstream as a from:port ticket.
INSTALL_BIN='/Applications/Aleph One/Aleph One.app/Contents/MacOS/Aleph One'

_ao_paths() {
	local app_dir="/Applications/Aleph One"
	AO_EXEC="$app_dir/Aleph One.app/Contents/MacOS/Aleph One"
	AO_DATA="$app_dir/Scenarios/Marathon 2"
	AO_DEMOS="$AO_DATA/Demos"
	AO_FILM="$AO_DEMOS/L00.filA"
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
# leaves the game running a further ~6s so bench-evidence.sh's own two
# liveness pings (return + 3s apart) sample a genuinely still-live process,
# and schedules its own stop -- detached, on the remote side -- so nothing
# leaks regardless of what the caller does next.
bench_launch() {
	local host="$1" round="$2" workdir="$3"
	_ao_paths
	local target="${ALEPHONE_BENCH_TARGET:-60}"
	local log_secs="${ALEPHONE_BENCH_LOG_SECS:-2}"
	local secs="${ALEPHONE_BENCH_SECS:-12}"
	local run_home; run_home="$(_ao_run_home)"
	local log_path; log_path="$(_ao_log_path)"

	local remote_cmd
	remote_cmd=$(cat <<EOF
set -u
if [ ! -x "$AO_EXEC" ] || [ ! -f "$AO_FILM" ]; then
	echo "BENCH FAIL: install or demo film missing"
	echo "===BENCH_META==="
	echo "ALIVE=no"
	echo "PID="
	exit 0
fi
rm -rf "$run_home"; mkdir -p "$run_home/home"
( cd "$AO_APP_DIR" && HOME="$run_home/home" ALEPHONE_FPS_LOG=$log_secs ALEPHONE_FPS_TARGET=$target \
	exec "$AO_EXEC" -s --no-chooser -Q -l "$AO_DEMOS" "$AO_DATA" "$AO_FILM" \
) > "$log_path" 2>&1 < /dev/null &
pid=\$!
sleep $secs
alive=no; kill -0 "\$pid" 2>/dev/null && alive=yes
( sleep 6
  osascript -e 'tell application "Aleph One" to quit' >/dev/null 2>&1 || true
  for i in 1 2 3 4 5; do kill -0 "\$pid" 2>/dev/null || exit 0; sleep 1; done
  kill "\$pid" 2>/dev/null || true
  for i in 1 2 3; do kill -0 "\$pid" 2>/dev/null || exit 0; sleep 1; done
  kill -9 "\$pid" 2>/dev/null || true
) > /dev/null 2>&1 < /dev/null &
disown
cat "$log_path"
echo "===BENCH_META==="
echo "ALIVE=\$alive"
echo "PID=\$pid"
EOF
)
	local out meta_line alive pid
	out="$(_ao_sh "$host" "$remote_cmd")"
	meta_line="$(printf '%s\n' "$out" | grep -n '^===BENCH_META===$' | head -1 | cut -d: -f1)"

	if [ -n "$meta_line" ]; then
		printf '%s\n' "$out" | sed -n "1,$((meta_line - 1))p" > "$workdir/log.txt"
		alive="$(printf '%s\n' "$out" | sed -n "$((meta_line + 1))p" | sed 's/^ALIVE=//')"
		pid="$(printf '%s\n' "$out" | sed -n "$((meta_line + 2))p" | sed 's/^PID=//')"
	else
		printf '%s\n' "$out" > "$workdir/log.txt"
		alive=no; pid=
	fi

	grep '^fps-log: [0-9]' "$workdir/log.txt" 2>/dev/null | sed 1d | awk '{print $2}' > "$workdir/stats.txt"
	echo fps > "$workdir/stats.unit"

	if grep -q '^BENCH FAIL' "$workdir/log.txt" 2>/dev/null; then
		echo "EXIT=1"
	else
		echo "EXIT=0"
	fi
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
