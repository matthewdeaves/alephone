#!/usr/bin/env bash
# Build Aleph One's private SDL2 2.0.3 prefix for the generic PPC/G3 target.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN=bd33187009c97e2c06bdeb10d7faf3ba60abdda5
PATCH_FILE="$REPO_ROOT/scripts/patches/sdl2-ppc-g3-no-altivec.patch"
VIDEO_PATCH_FILE="$REPO_ROOT/scripts/patches/sdl2-ppc-g3-cocoa-video-no-altivec.patch"
DISPLAY_PATCH_FILE="$REPO_ROOT/scripts/patches/sdl2-ppc-panther-display-name.patch"
FILESYSTEM_PATCH_FILE="$REPO_ROOT/scripts/patches/sdl2-ppc-panther-filesystem.patch"
DRAIN_PATCH_FILE="$REPO_ROOT/scripts/patches/sdl2-ppc-panther-drain.patch"
BUILD_HOST_CLAIMED=0

if [ -z "${BUILD_HOST:-}" ]; then
	BUILD_HOST="$(BUILD_LOCK_WAIT="${BUILD_LOCK_WAIT:-900}" \
		"$REPO_ROOT/scripts/pick-build-host.sh" --acquire "alephone SDL2 PPC")" || {
		echo "build-sdl2-ppc.sh: no free Intel build host" >&2
		exit 1
	}
	BUILD_HOST_CLAIMED=1
	echo "[sdl2-ppc] claimed build host: $BUILD_HOST"
fi
trap '[ "$BUILD_HOST_CLAIMED" = 1 ] && "$REPO_ROOT/scripts/pick-build-host.sh" --release "$BUILD_HOST" >/dev/null 2>&1; true' EXIT

scp -q "$PATCH_FILE" "$BUILD_HOST:/tmp/alephone-sdl2-ppc-g3-no-altivec.patch"
scp -q "$VIDEO_PATCH_FILE" "$BUILD_HOST:/tmp/alephone-sdl2-ppc-g3-cocoa-video-no-altivec.patch"
scp -q "$DISPLAY_PATCH_FILE" "$BUILD_HOST:/tmp/alephone-sdl2-ppc-panther-display-name.patch"
scp -q "$FILESYSTEM_PATCH_FILE" "$BUILD_HOST:/tmp/alephone-sdl2-ppc-panther-filesystem.patch"
scp -q "$DRAIN_PATCH_FILE" "$BUILD_HOST:/tmp/alephone-sdl2-ppc-panther-drain.patch"
ssh "$BUILD_HOST" 'bash -s' -- "$PIN" /tmp/alephone-sdl2-ppc-g3-no-altivec.patch /tmp/alephone-sdl2-ppc-g3-cocoa-video-no-altivec.patch /tmp/alephone-sdl2-ppc-panther-display-name.patch /tmp/alephone-sdl2-ppc-panther-filesystem.patch /tmp/alephone-sdl2-ppc-panther-drain.patch <<'REMOTE_BUILD'
set -euo pipefail

PIN="$1"
PATCH_FILE="$2"
VIDEO_PATCH_FILE="$3"
DISPLAY_PATCH_FILE="$4"
FILESYSTEM_PATCH_FILE="$5"
DRAIN_PATCH_FILE="$6"
ROOT="$HOME/oldmac/alephone"
SHARED="$HOME/oldmac/vendor/panther-sdl2"
SRC="$ROOT/panther-sdl2"
BUILD="$ROOT/panther-sdl2-build.$$"
FINAL="$ROOT/sdl2-ppc-tiger103"
STAGE="$ROOT/.sdl-stage.$$"
MARKER=.alephone-sdl2-ppc-provenance
PATCH_DIGEST="$(cat "$PATCH_FILE" "$VIDEO_PATCH_FILE" "$DISPLAY_PATCH_FILE" "$FILESYSTEM_PATCH_FILE" "$DRAIN_PATCH_FILE" | shasum -a 256 | awk '{print $1}')"
EXPECTED="SDL2 2.0.3 pin=$PIN patch-sha256=$PATCH_DIGEST patches=g3-no-altivec,g3-cocoa-video-no-altivec,panther-display-name,panther-filesystem,panther-drain target=powerpc-apple-darwin8 cpu=generic-g3 flags=-arch,ppc,-mmacosx-version-min=10.3,--disable-altivec,--disable-joystick"
OBJC="$HOME/gcc14-ppc-objc/bin/powerpc-apple-darwin8-gcc"
GCCBASE="$HOME/gcc14-ppc-objc/lib/gcc/powerpc-apple-darwin8/14.2.0"
# old-mac-build-host#81: not every build host has the plain C/C++-only
# ~/gcc14-ppc yet (as of 2026-09-13, only mini-intel2 has the ObjC-capable
# ~/gcc14-ppc-objc; mini-intel's plain toolchain predates it and hasn't
# caught up). SDL2 2.0.3's build is plain C at its core (only the Cocoa
# backend's .m files need real Objective-C) and gcc14-ppc-objc's gcc
# compiles plain C fine, so fall back to it -- detect by existence, not
# hostname, matching this repo's existing convention (build.sh:56-58's SDK
# path). CXX has no fallback: gcc14-ppc-objc was built --enable-languages=
# c,objc (no C++) and SDL2 2.0.3 doesn't need one; if that ever changes,
# this will fail loudly on the missing binary rather than silently.
if [ -x "$HOME/gcc14-ppc/bin/powerpc-apple-darwin8-gcc" ]; then
	CC="$HOME/gcc14-ppc/bin/powerpc-apple-darwin8-gcc"
	CXX="$HOME/gcc14-ppc/bin/powerpc-apple-darwin8-g++"
	CXXCPP_OVERRIDE=""
else
	echo "[sdl2-ppc] no plain ~/gcc14-ppc on this host -- using ~/gcc14-ppc-objc's gcc for C too"
	CC="$OBJC"
	CXX="$OBJC"
	# autoconf's AC_PROG_CXXCPP is unconditional and fatal on failure, even
	# though SDL2 2.0.3 has zero .cpp files and never actually invokes
	# CXXCPP for real compilation in this configuration. This gcc build
	# rejects any *.cpp-suffixed input at the driver level regardless of
	# content ("C++ compiler not installed on this system"), which fails
	# autoconf's own conftest.cpp sanity check outright -- there is no
	# flag/workaround for that gcc-side behavior, so satisfy the check with
	# the build host's native macOS cpp instead (only ever asked to
	# preprocess autoconf's own trivial test snippet, never real source).
	CXXCPP_OVERRIDE="/usr/bin/cpp"
fi

if [ -d /Developer/SDKs/MacOSX10.3.9.sdk ]; then
	SDK=/Developer/SDKs/MacOSX10.3.9.sdk
elif [ -d "$HOME/SDKs/MacOSX10.3.9.sdk" ]; then
	SDK="$HOME/SDKs/MacOSX10.3.9.sdk"
else
	echo "sdl2-ppc: MacOSX10.3.9 SDK is unavailable" >&2
	exit 1
fi

if [ -x "$FINAL/bin/sdl2-config" ] && [ -f "$FINAL/lib/libSDL2.a" ] && \
	[ "$(cat "$FINAL/$MARKER" 2>/dev/null || true)" = "$EXPECTED" ]; then
	echo "[sdl2-ppc] verified existing port-owned prefix: $FINAL"
	exit 0
fi

# Do not assert $SHARED's current HEAD matches our pin: it is a shared
# mirror other ports (e.g. old-mac-halflife) also use and check out their
# own commits into, so its live HEAD can legitimately be anything. Only
# require that our pinned commit exists as an object there (a real clone
# carries full history, not just the checked-out ref) and explicitly check
# it out in our own private clone instead of trusting SHARED's HEAD.
git -C "$SHARED" cat-file -e "$PIN" 2>/dev/null
mkdir -p "$ROOT"
if [ ! -d "$SRC/.git" ]; then
	git clone "$SHARED" "$SRC"
fi
if ! git -C "$SRC" checkout --detach "$PIN" >/tmp/alephone-sdl2-ppc-checkout.log 2>&1; then
	git -C "$SRC" fetch "$SHARED" "$PIN"
	git -C "$SRC" checkout --detach "$PIN"
fi
test "$(git -C "$SRC" rev-parse HEAD)" = "$PIN"
# alephone#36: FILESYSTEM_PATCH_FILE used to be scp'd to the host and hashed
# into the provenance marker below without ever actually being applied here
# -- a hardcoded perl -0pi substitution did the real work instead, so the
# tracked patch file and the marker's claim about it were both fiction. Now
# applied through the same mechanism as every other patch, so there is only
# one real source of truth for what's actually in the tree.
for patch in "$PATCH_FILE" "$VIDEO_PATCH_FILE" "$DISPLAY_PATCH_FILE" "$FILESYSTEM_PATCH_FILE" "$DRAIN_PATCH_FILE"; do
	if git -C "$SRC" apply --recount --reverse --check "$patch" 2>/dev/null; then
		echo "[sdl2-ppc] source patch already applied: $(basename "$patch")"
	else
		git -C "$SRC" apply --recount --check "$patch"
		git -C "$SRC" apply --recount "$patch"
	fi
done

WRAPPER="$ROOT/.sdl2-cc"
cat > "$WRAPPER" <<'EOF'
#!/bin/sh
# SDL2 2.0.3's configure unconditionally adds -fpascal-strings for any
# Darwin/macOS target (an Apple-GCC-only extension, used for old Mac
# Toolbox Pascal-string literals) -- GCC 14 (this cross-toolchain, a
# mainline FSF build, not Apple's fork) does not implement it at all and
# aborts with "unrecognized command-line option". Nothing in this file
# uses Pascal string literals, so dropping the flag is safe; strip it here
# rather than patching SDL2's own configure/Makefile.
args=""
for arg in "$@"; do
	case "$arg" in
		-fpascal-strings) continue ;;
	esac
	args="$args $arg"
done
set -- $args
for arg in "$@"; do
	case "$arg" in
		*.m|objective-c) exec "$ALEPHONE_SDL_OBJC" -fnext-runtime -fobjc-exceptions -nostdinc \
			-isystem "$ALEPHONE_SDL_GCCBASE/include" \
			-isystem "$ALEPHONE_SDL_GCCBASE/../../../../powerpc-apple-darwin8/include" \
			-isystem "$ALEPHONE_SDL_SDK/usr/include" \
			-iframework "$ALEPHONE_SDL_SDK/System/Library/Frameworks" \
			-include "$HOME/ptrdiff-compat-full.h" "$@" ;;
	esac
done
exec "$ALEPHONE_SDL_CC" "$@"
EOF
chmod 700 "$WRAPPER"
export ALEPHONE_SDL_CC="$CC" ALEPHONE_SDL_OBJC="$OBJC"
export ALEPHONE_SDL_GCCBASE="$GCCBASE" ALEPHONE_SDL_SDK="$SDK"

FLAGS="-O2 -arch ppc -mcpu=750 -mmacosx-version-min=10.3 -isysroot $SDK -include stddef.h"
CXXCPP="${CXXCPP_OVERRIDE:-$CXX -E $FLAGS}"
mkdir "$BUILD" "$STAGE"
cd "$BUILD"
"$SRC/configure" \
	--host=powerpc-apple-darwin8 --prefix="$FINAL" \
	--disable-shared --enable-static --disable-altivec --disable-joystick --disable-haptic --without-x \
	CC="$WRAPPER" CPP="$WRAPPER -E $FLAGS" CXX="$CXX" CXXCPP="$CXXCPP" \
	CFLAGS="$FLAGS -Wno-error=incompatible-pointer-types" CXXFLAGS="$FLAGS" LDFLAGS="$FLAGS" \
	> /tmp/alephone-sdl2-ppc-configure.log 2>&1 || { tail -50 /tmp/alephone-sdl2-ppc-configure.log; exit 1; }
make -j2 > /tmp/alephone-sdl2-ppc-build.log 2>&1 || { tail -50 /tmp/alephone-sdl2-ppc-build.log; exit 1; }
make install DESTDIR="$STAGE" > /tmp/alephone-sdl2-ppc-install.log 2>&1 || { tail -50 /tmp/alephone-sdl2-ppc-install.log; exit 1; }

CANDIDATE="$STAGE$FINAL"
printf '%s\n' "$EXPECTED" > "$CANDIDATE/$MARKER"
test -x "$CANDIDATE/bin/sdl2-config"
test -f "$CANDIDATE/lib/libSDL2.a"
test "$(cat "$CANDIDATE/$MARKER")" = "$EXPECTED"
if [ -e "$FINAL" ]; then
	mv "$FINAL" "$FINAL.previous.$(date +%s)"
fi
mv "$CANDIDATE" "$FINAL"
# Best-effort cleanup only: the real work (promoting $FINAL above) has
# already succeeded, so a leftover staging directory here (e.g. a stray file
# from `make install`, or a remote $HOME that isn't exactly two path
# segments) must not make set -e abort the script and report a false build
# failure.
rmdir "$STAGE$ROOT" "$STAGE$HOME/oldmac" "$STAGE$HOME" "$STAGE/Users" "$STAGE" 2>/dev/null \
	|| echo "[sdl2-ppc] note: could not fully remove staging dir $STAGE (non-fatal, leftover may need manual cleanup)"
echo "[sdl2-ppc] staged and promoted verified prefix: $FINAL"
REMOTE_BUILD
