#!/usr/bin/env bash
# migrate-home-layout.sh - move this repo's build scratch and dependency
# prefixes on a build host from loose ~/alephone-* dirs into ~/oldmac/alephone/
# (#27, fleet rule old-mac-build-host#73: nothing loose in $HOME).
#
# usage: scripts/migrate-home-layout.sh [HOST]
#   BUILD_HOST set  -> run against it; the caller already holds its lock.
#   otherwise       -> claim HOST through the picker for the duration.
#
# Idempotent and cheap once done, so build.sh and the deps scripts call it on
# every run: a host that was offline at migration time (mini-intel, 2026-09-22)
# moves itself on its next build.
#
# Only the .pc/.la files in the deps prefixes embed the old absolute path
# (measured on imac-2019: no binary or static archive does), so a move plus a
# path rewrite in those files is the whole migration, not a deps rebuild.
# A dir that already exists at the new location is never overwritten; the
# legacy copy is left in place and reported.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILD_HOST_CLAIMED=0
if [ -z "${BUILD_HOST:-}" ]; then
	host="${1:?usage: $0 HOST (or set BUILD_HOST when already holding its lock)}"
	export BENCH_LOCK_CLAIM="${BENCH_LOCK_CLAIM:-$$.$(date +%s).${RANDOM:-0}}"
	BUILD_HOST="$(BUILD_LOCK_WAIT="${BUILD_LOCK_WAIT:-900}" \
		"$REPO_ROOT/scripts/pick-build-host.sh" --acquire-host "$host" "alephone migrate-home-layout")" || {
		echo "migrate-home-layout.sh: could not claim $host; see scripts/pick-build-host.sh --status" >&2
		exit 1
	}
	BUILD_HOST_CLAIMED=1
fi
trap '[ "$BUILD_HOST_CLAIMED" = 1 ] && "$REPO_ROOT/scripts/pick-build-host.sh" --release "$BUILD_HOST" >/dev/null 2>&1; true' EXIT

ssh "$BUILD_HOST" 'bash -s' << 'REMOTE_MIGRATE'
set -euo pipefail

ROOT="$HOME/oldmac/alephone"
mkdir -p "$ROOT"

# ~/alephone-<name> -> ~/oldmac/alephone/<name>
NAMES="build-ppc build-x86_64 ppc-deps intel-deps intel-deps-native deps-src deps-build deps-build-intel"
for name in $NAMES; do
	old="$HOME/alephone-$name" new="$ROOT/$name"
	[ -e "$old" ] || continue
	if [ -e "$new" ]; then
		echo "[migrate] $(hostname -s): both $old and $new exist; left $old in place" >&2
		continue
	fi
	mv "$old" "$new"
	echo "[migrate] $(hostname -s): $old -> $new"
done

# Rewrite every legacy path in every prefix, not just a prefix's own: one
# prefix's .pc/.la can point into another (openal.pc -> ppc-deps). The
# (?![\w-]) keeps .../alephone-intel-deps from matching inside
# .../alephone-intel-deps-native.
shopt -s nullglob
for f in "$ROOT"/*deps*/lib/pkgconfig/*.pc "$ROOT"/*deps*/lib/*.la; do
	grep -q "$HOME/alephone-" "$f" || continue
	ALT="${NAMES// /|}" perl -pi -e \
		's#\Q$ENV{HOME}\E/alephone-($ENV{ALT})(?![\w-])#$ENV{HOME}/oldmac/alephone/$1#g' "$f"
done

# build-sdl2-ppc.sh used to leave its per-run build dir behind and keep every
# previous prefix (#27). Safe under the host lock: no other build is running.
rm -rf "$ROOT"/panther-sdl2-build.* "$ROOT"/.sdl-stage.*
# Keep only the newest rollback prefix; the glob sorts by its fixed-width
# epoch suffix.
prev=("$ROOT"/sdl2-ppc-tiger103.previous.*)
for ((i = 0; i + 1 < ${#prev[@]}; i++)); do rm -rf "${prev[$i]}"; done
REMOTE_MIGRATE
