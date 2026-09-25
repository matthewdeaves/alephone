#!/usr/bin/env bash
# build-sdl2-i386.sh - Aleph One's private i386 SDL2 2.0.3 prefix at a 10.4
# floor (alephone#30), statically linked into the i386 slice like ppc's.
#
# Source: deps' fork, matthewdeaves/SDL tag retro/tiger-i386-base (SDL#7):
# the same SDL 2.0.3 Panther fork the ppc slice uses, plus two Cocoa fixes
# a 10.4 build needs on 10.6+ (without them SDL_Init(VIDEO) finds no displays).
# Built with deps' recipe on imac-2019: Apple clang and the real 10.4u SDK.
# The i686 GCC 14 has no Objective-C, and SDL's Cocoa backend needs it.
# The finished prefix is then copied to mini-intel2, where build.sh links the
# i386 slice. Both hosts' $HOME is /Users/mini, so the prefix path (which
# sdl2-config hardcodes) is the same on both.
#
# usage: scripts/build-sdl2-i386.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_HOST="${ALEPHONE_SDL_I386_BUILD_HOST:-imac-2019}"
LINK_HOST="${ALEPHONE_I386_LINK_HOST:-mini-intel2}"
TAG=retro/tiger-i386-base
PIN=4551b9a9598fb12f695882fa327af93ce7f93ff2
PREFIX=/Users/mini/oldmac/alephone/sdl2-i386-tiger104
MARKER=.alephone-sdl2-i386-provenance
EXPECTED="SDL2 2.0.3 pin=$PIN (matthewdeaves/SDL@$TAG) target=i386-apple-darwin8 flags=-arch,i386,-mmacosx-version-min=10.4,--disable-haptic"

if ssh "$LINK_HOST" "test -f '$PREFIX/lib/libSDL2.a' && test \"\$(cat '$PREFIX/$MARKER' 2>/dev/null)\" = '$EXPECTED'"; then
	echo "[sdl2-i386] verified existing prefix on $LINK_HOST: $PREFIX"
	exit 0
fi

export BENCH_LOCK_CLAIM="${BENCH_LOCK_CLAIM:-alephone.sdl2i386.$$.$(date +%s)}"
CLAIMED=""
TMP="$(mktemp -d)"
cleanup() {
	for h in $CLAIMED; do "$REPO_ROOT/scripts/shared.sh" pick-bench-host.sh --release "$h" >/dev/null 2>&1; done
	rm -rf "$TMP"
}
trap cleanup EXIT
claim() {
	[ "${RETRO_BENCH_LOCK:-}" = "$1" ] && return 0
	BENCH_LOCK_WAIT="${BENCH_LOCK_WAIT:-900}" "$REPO_ROOT/scripts/shared.sh" pick-bench-host.sh --acquire "$1" "alephone build-sdl2-i386" >/dev/null || {
		echo "build-sdl2-i386.sh: $1 is not free; see scripts/shared.sh pick-bench-host.sh --status" >&2
		exit 1
	}
	CLAIMED="$CLAIMED $1"
}
claim "$BUILD_HOST"

echo "[sdl2-i386] building $TAG on $BUILD_HOST..."
# ssh joins its arguments into one string for the remote login shell (zsh on
# imac-2019), so quote each one: EXPECTED has spaces and parentheses.
ssh "$BUILD_HOST" "bash -s -- $(printf '%q ' "$TAG" "$PIN" "$PREFIX" "$MARKER" "$EXPECTED")" << 'REMOTE_BUILD'
set -euo pipefail
TAG="$1"; PIN="$2"; PREFIX="$3"; MARKER="$4"; EXPECTED="$5"
ROOT="$HOME/oldmac/alephone"
SRC="$ROOT/sdl-i386-src"
BUILD="$ROOT/.sdl-i386-build.$$"
STAGE="$ROOT/.sdl-i386-stage.$$"
SDK="$HOME/SDKs/MacOSX10.4u.sdk"
[ -d "$SDK" ] || { echo "build-sdl2-i386.sh: no $SDK" >&2; exit 1; }
mkdir -p "$ROOT"
if [ ! -d "$SRC/.git" ]; then
	git clone --depth 1 --branch "$TAG" https://github.com/matthewdeaves/SDL.git "$SRC" > /tmp/alephone-sdl2-i386.log 2>&1
fi
if [ "$(git -C "$SRC" rev-parse HEAD)" != "$PIN" ]; then
	git -C "$SRC" fetch --depth 1 origin tag "$TAG" >> /tmp/alephone-sdl2-i386.log 2>&1
	git -C "$SRC" checkout --detach "$PIN" >> /tmp/alephone-sdl2-i386.log 2>&1
fi
test "$(git -C "$SRC" rev-parse HEAD)" = "$PIN"

# Out of tree: the fork commits a ppc-generated include/SDL_config.h.
FLAGS="-arch i386 -mmacosx-version-min=10.4 -isysroot $SDK"
mkdir "$BUILD" "$STAGE"
cd "$BUILD"
"$SRC/configure" --host=i386-apple-darwin8 --prefix="$PREFIX" \
	--disable-shared --enable-static --without-x --disable-haptic \
	CC="clang $FLAGS" CFLAGS="-O2 $FLAGS" LDFLAGS="$FLAGS" \
	>> /tmp/alephone-sdl2-i386.log 2>&1 || { tail -40 /tmp/alephone-sdl2-i386.log; exit 1; }
make -j4 >> /tmp/alephone-sdl2-i386.log 2>&1 || { tail -40 /tmp/alephone-sdl2-i386.log; exit 1; }
make install DESTDIR="$STAGE" >> /tmp/alephone-sdl2-i386.log 2>&1 || { tail -40 /tmp/alephone-sdl2-i386.log; exit 1; }

CANDIDATE="$STAGE$PREFIX"
printf '%s\n' "$EXPECTED" > "$CANDIDATE/$MARKER"
test -x "$CANDIDATE/bin/sdl2-config"
lipo -info "$CANDIDATE/lib/libSDL2.a" | grep -q 'architecture: i386'
rm -rf "$PREFIX"
mkdir -p "$(dirname "$PREFIX")"
mv "$CANDIDATE" "$PREFIX"
cd "$ROOT" && rm -rf "$BUILD" "$STAGE" /tmp/alephone-sdl2-i386.log
echo "[sdl2-i386] libSDL2.a sha256 $(shasum -a 256 "$PREFIX/lib/libSDL2.a" | cut -d' ' -f1)"
REMOTE_BUILD

echo "[sdl2-i386] copying the prefix to $LINK_HOST..."
rsync -a "$BUILD_HOST:$PREFIX/" "$TMP/prefix/"
# One claim at a time (fleet rule 4a1e530): drop the build host before
# taking the link host, never hold one while waiting for the other.
for h in $CLAIMED; do "$REPO_ROOT/scripts/shared.sh" pick-bench-host.sh --release "$h" >/dev/null 2>&1; done
CLAIMED=""
claim "$LINK_HOST"
ssh "$LINK_HOST" "rm -rf '$PREFIX' && mkdir -p '$(dirname "$PREFIX")'"
rsync -a "$TMP/prefix/" "$LINK_HOST:$PREFIX/"
ssh "$LINK_HOST" "test \"\$(cat '$PREFIX/$MARKER')\" = '$EXPECTED'"
echo "[sdl2-i386] prefix ready on $LINK_HOST: $PREFIX"
