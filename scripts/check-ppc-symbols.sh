#!/usr/bin/env bash
# check-ppc-symbols.sh - the PPC weak-linking gate (.claude/rules/
# legacy-mac-hardware.md): every non-weak undefined symbol in the ppc slice
# must be defined by some library in the Mac OS X 10.3.9 SDK. One 10.4-only
# symbol links fine on the build host and then dyld aborts at launch on a
# 10.3.9 G3.
#
# usage: scripts/check-ppc-symbols.sh [ppc-binary]   (default build/alephone-ppc)
# Runs on a build host (it has the ppc-aware cctools nm and the SDK); claims
# one through the picker unless BUILD_HOST is set by a caller holding it.
# Static check against SDK stubs, not a launch on real hardware.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# ARCH=i386 runs the same gate for the i386 slice (#30): the i686 cross nm on
# mini-intel2 against the 10.4u SDK, the floor that slice declares.
ARCH="${ARCH:-ppc}"
case "$ARCH" in
	ppc)  NM_PATH='gcc14-ppc/bin/powerpc-apple-darwin8-nm'; SDK_NAME=MacOSX10.3.9.sdk ;;
	i386) NM_PATH='oldmac/gcc14-i686/bin/i686-apple-darwin8-nm'; SDK_NAME=MacOSX10.4u.sdk
	      export BUILD_HOSTS="${BUILD_HOSTS:-mini-intel2}" ;;
	*) echo "check-ppc-symbols.sh: ARCH must be ppc or i386" >&2; exit 2 ;;
esac
BIN="${1:-$REPO_ROOT/build/alephone-$ARCH}"
[ -f "$BIN" ] || { echo "check-ppc-symbols.sh: $BIN not found" >&2; exit 1; }

BUILD_HOST_CLAIMED=0
if [ -z "${BUILD_HOST:-}" ]; then
	export BENCH_LOCK_CLAIM="${BENCH_LOCK_CLAIM:-alephone.symcheck.$$.$(date +%s)}"
	BUILD_HOST="$(BUILD_LOCK_WAIT="${BUILD_LOCK_WAIT:-900}" \
		"$REPO_ROOT/scripts/pick-build-host.sh" --acquire "alephone $ARCH symbol check")" || {
		echo "check-ppc-symbols.sh: no free build host" >&2
		exit 1
	}
	BUILD_HOST_CLAIMED=1
fi
trap '[ "$BUILD_HOST_CLAIMED" = 1 ] && "$REPO_ROOT/scripts/pick-build-host.sh" --release "$BUILD_HOST" >/dev/null 2>&1; true' EXIT

ssh "$BUILD_HOST" 'mkdir -p ~/oldmac/alephone/symcheck'
scp -q "$BIN" "$BUILD_HOST:oldmac/alephone/symcheck/bin"

ssh "$BUILD_HOST" "bash -s -- $NM_PATH $SDK_NAME" << 'REMOTE_CHECK'
set -euo pipefail
NM_PATH="$1"; SDK_NAME="$2"
W=~/oldmac/alephone/symcheck
trap 'rm -rf "$W"' EXIT
NM="$HOME/$NM_PATH"
[ -x "$NM" ] || { echo "check-ppc-symbols: no nm at $NM" >&2; exit 1; }
if [ -d "/Developer/SDKs/$SDK_NAME" ]; then SDK="/Developer/SDKs/$SDK_NAME"
elif [ -d "$HOME/SDKs/$SDK_NAME" ]; then SDK="$HOME/SDKs/$SDK_NAME"
else echo "check-ppc-symbols: no $SDK_NAME" >&2; exit 1; fi

# Every symbol any library in the SDK defines (a superset of what is
# linked; the question here is only "does it exist on 10.3.9 at all").
find "$SDK/usr/lib" "$SDK/System/Library/Frameworks" -type f \( -name '*.dylib' -o -perm -u+x \) 2>/dev/null |
	while read -r lib; do "$NM" -gU "$lib" 2>/dev/null; done |
	awk 'NF >= 3 {print $NF}' | sort -u > "$W/defined"

"$NM" -m "$W/bin" | awk '/\(undefined\)/ && !/weak external/ {
	for (i = 1; i < NF; i++) if ($i == "external") { print $(i + 1); break } }' | sort -u > "$W/strong"
weak=$("$NM" -m "$W/bin" | grep -c '(undefined) weak external' || true)
missing=$(comm -23 "$W/strong" "$W/defined")

echo "check-ppc-symbols: $(wc -l < "$W/strong" | tr -d ' ') strong undefined, $weak weak, against $(wc -l < "$W/defined" | tr -d ' ') SDK symbols ($SDK)"
if [ -n "$missing" ]; then
	echo "check-ppc-symbols: FAIL -- not in $SDK_NAME:" >&2
	echo "$missing" | sed 's/^/  /' >&2
	exit 1
fi
echo "check-ppc-symbols: PASS"
REMOTE_CHECK
