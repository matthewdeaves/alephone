#!/usr/bin/env bash
# build-arm64.sh - build the arm64 (Apple Silicon) slice.
#
# This one runs HERE, on the workstation, not on a remote build host. Unlike
# ppc/x86_64 (scripts/build.sh), which cross-compile on old Intel minis, arm64
# is native: this machine IS the only Apple Silicon Mac in the fleet
# (old-mac-build-host docs/apple-silicon-arm64.md), so there is nothing to
# cross-compile from and nowhere else to build it.
#
# Unlike ppc/x86_64, this slice deliberately tracks upstream Aleph One's
# CURRENT engine and CURRENT dependency versions (alephone#17) -- there is no
# ancient-toolchain or big-endian constraint here to pin anything back for.
# Six deps, same as the other two slices, but modern ones: Homebrew for
# boost/asio/freetype/libsndfile(+codec chain)/libpng, a from-source static
# SDL2_ttf and openal-soft (Homebrew ships those as dylibs only, or with
# extra transitive deps this port doesn't want), and the fleet's own pinned
# SDL2 2.32.4 (~/oldmac/sdl2-arm64) -- Homebrew's own "sdl2" is keg-only,
# shadowed by sdl2-compat, and using the fleet's already-verified build is
# both simpler and consistent with every other port here.
#
# usage: scripts/build-arm64.sh
# post:  build/alephone-arm64 present, ad-hoc signed, arm64-only, and
#        build/deps-arm64/libSDL2-2.0.0.dylib for package-dmg.sh to bundle.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$REPO_ROOT/scripts/source-stamp.sh"
. "$REPO_ROOT/scripts/source-stamp-excludes.sh"

if [ "$(uname -m)" != "arm64" ]; then
	echo "build-arm64.sh: this machine is $(uname -m), not arm64." >&2
	echo "build-arm64.sh: the arm64 slice must be built on an Apple Silicon Mac." >&2
	exit 1
fi

VMIN=11.0
# 11.0, not lower: no arm64 Mac shipped before Big Sur, so anything lower
# would only be a fiction (same reasoning old-mac-quakespasm's build-arm64.sh
# uses for the same VMIN).

SDL_DIR="$HOME/oldmac/sdl2-arm64"
DEPS="$HOME/oldmac/alephone-arm64-deps"
STATICONLY="$DEPS/static-only"
BOOST="$(brew --prefix boost)"
ASIO="$(brew --prefix asio)"
FREETYPE="$(brew --prefix freetype)"
SNDFILE="$(brew --prefix libsndfile)"

if [ ! -f "$SDL_DIR/lib/libSDL2-2.0.0.dylib" ]; then
	echo "build-arm64.sh: $SDL_DIR not found." >&2
	echo "build-arm64.sh: this is the fleet's shared pinned SDL2 2.32.4 build" >&2
	echo "  (old-mac-build-host docs/apple-silicon-arm64.md) -- provision it the" >&2
	echo "  same way that repo's build-arm64.sh drivers do, then re-run." >&2
	exit 1
fi

# ---------------------------------------------------------------------------
# ensure_arm64_deps: build the two deps Homebrew can't provide in the shape
# this port needs, once, and leave a marker so re-runs are instant.
#
# - SDL2_ttf: Homebrew's own build links against sdl2-compat (an SDL3 shim,
#   not real SDL2) and pulls in harfbuzz. Built here from source instead,
#   statically, against the fleet's own pinned SDL2 -- matching how ppc/
#   x86_64 already do it (their DEPS/lib/libSDL2_ttf.a), just with modern
#   source instead of an old pinned tarball.
# - openal-soft: Homebrew ships it as a dylib only. Built here statically
#   from the same upstream release Homebrew currently carries (1.25.2), so
#   the arm64 slice needs no bundled OpenAL dylib at all, same invariant as
#   ppc/x86_64.
#
#   That build needs one small source patch: Xcode 26 / clang 21's
#   CoreAudioTypes.framework header trips openal-soft's own
#   -Werror=function-effects check on coreaudio.cpp's inputProc lambdas
#   ("attribute 'nonblocking' should not be added via type conversion") --
#   a real upstream/SDK version mismatch (nothing in this codebase, or in
#   openal-soft's actual behavior, is affected), not something to carry as
#   a runtime workaround. Force HAVE_WFUNCTION_EFFECTS off in its
#   CMakeLists.txt rather than fighting compiler-flag precedence: openal-
#   soft's own CMakeLists appends -Werror=function-effects AFTER any
#   CMAKE_CXX_FLAGS this script could pass, so -Wno-* flags from here lose.
#
# static-only/: a directory of symlinks to ONLY the .a of each Homebrew dep
# this port also has a .dylib for (boost_filesystem, freetype, libsndfile,
# libpng, and libsndfile's own codec chain: FLAC/vorbis/ogg/opus/mpg123/
# mp3lame). Homebrew ships both forms side by side, and a bare -lname
# resolves to whichever -L directory is searched first; putting ONLY the
# static archive where the linker looks first is more reliable than fighting
# per-package link-line ordering, and it's what keeps this slice down to a
# single bundled dylib (SDL2) instead of pulling in a chain of Homebrew-
# relative dylib paths that would crash-at-launch on any Mac without that
# exact Homebrew layout -- precisely the class of bug alephone#5 already hit
# once this fleet, for x86_64's SDL2.
ensure_arm64_deps() {
	mkdir -p "$DEPS/lib" "$DEPS/include" "$STATICONLY"

	if [ ! -f "$DEPS/lib/libSDL2_ttf.a" ]; then
		echo "[build-arm64] building static SDL2_ttf (one-time)..."
		_work="$(mktemp -d)"
		trap '[ -n "${_work:-}" ] && rm -rf "$_work"' RETURN
		curl -sL "https://github.com/libsdl-org/SDL_ttf/releases/download/release-2.24.0/SDL2_ttf-2.24.0.tar.gz" \
			-o "$_work/SDL2_ttf-2.24.0.tar.gz"
		tar xzf "$_work/SDL2_ttf-2.24.0.tar.gz" -C "$_work"
		cmake -S "$_work/SDL2_ttf-2.24.0" -B "$_work/SDL2_ttf-2.24.0/build" \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_OSX_DEPLOYMENT_TARGET="$VMIN" \
			-DBUILD_SHARED_LIBS=OFF \
			-DSDL2TTF_HARFBUZZ=OFF \
			-DSDL2TTF_VENDORED=OFF \
			-DSDL2TTF_SAMPLES=OFF \
			-DFREETYPE_INCLUDE_DIRS="$FREETYPE/include/freetype2" \
			-DFREETYPE_LIBRARY="$FREETYPE/lib/libfreetype.a" \
			-DSDL2_INCLUDE_DIR="$SDL_DIR/include/SDL2" \
			-DSDL2_LIBRARY="$SDL_DIR/lib/libSDL2.dylib" \
			-DCMAKE_INSTALL_PREFIX="$DEPS"
		cmake --build "$_work/SDL2_ttf-2.24.0/build" -j"$(sysctl -n hw.ncpu)"
		cmake --install "$_work/SDL2_ttf-2.24.0/build"
		rm -rf "$_work"
		trap - RETURN
	fi

	if [ ! -f "$DEPS/lib/libopenal.a" ]; then
		echo "[build-arm64] building static openal-soft 1.25.2 (one-time)..."
		_work="$(mktemp -d)"
		trap '[ -n "${_work:-}" ] && rm -rf "$_work"' RETURN
		curl -sL "https://github.com/kcat/openal-soft/archive/refs/tags/1.25.2.tar.gz" \
			-o "$_work/openal-soft-1.25.2.tar.gz"
		tar xzf "$_work/openal-soft-1.25.2.tar.gz" -C "$_work"
		_oal="$_work/openal-soft-1.25.2"
		# See the block comment above: neutralise the coreaudio.cpp / clang 21
		# function-effects false positive at its source (CMakeLists.txt), not
		# via a compiler flag that a later target_compile_options would win over.
		perl -0pi -e 's/check_cxx_compiler_flag\(-Wfunction-effects HAVE_WFUNCTION_EFFECTS\)\n\s*if\(HAVE_WFUNCTION_EFFECTS\)\n\s*list\(APPEND C_FLAGS \$<\$<COMPILE_LANGUAGE:CXX>:-Wfunction-effects>\)\n\s*endif\(\)/set(HAVE_WFUNCTION_EFFECTS FALSE)/' \
			"$_oal/CMakeLists.txt"
		cmake -S "$_oal" -B "$_oal/build" \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_OSX_DEPLOYMENT_TARGET="$VMIN" \
			-DLIBTYPE=STATIC \
			-DALSOFT_BACKEND_PORTAUDIO=OFF \
			-DALSOFT_BACKEND_PULSEAUDIO=OFF \
			-DALSOFT_UTILS=OFF \
			-DALSOFT_EXAMPLES=OFF \
			-DALSOFT_INSTALL_EXAMPLES=OFF \
			-DALSOFT_INSTALL_UTILS=OFF \
			-DCMAKE_INSTALL_PREFIX="$DEPS"
		cmake --build "$_oal/build" -j"$(sysctl -n hw.ncpu)"
		cmake --install "$_oal/build"
		rm -rf "$_work"
		trap - RETURN
	fi

	for pair in \
		"boost/lib/libboost_filesystem.a:$BOOST" \
		"freetype/lib/libfreetype.a:$FREETYPE" \
		"libsndfile/lib/libsndfile.a:$SNDFILE" \
		"libpng/lib/libpng16.a:$(brew --prefix libpng)" \
		"flac/lib/libFLAC.a:$(brew --prefix flac)" \
		"libogg/lib/libogg.a:$(brew --prefix libogg)" \
		"libvorbis/lib/libvorbis.a:$(brew --prefix libvorbis)" \
		"libvorbis/lib/libvorbisenc.a:$(brew --prefix libvorbis)" \
		"opus/lib/libopus.a:$(brew --prefix opus)" \
		"mpg123/lib/libmpg123.a:$(brew --prefix mpg123)" \
		"lame/lib/libmp3lame.a:$(brew --prefix lame)" \
		; do
		_rel="${pair%%:*}"; _prefix="${pair##*:}"
		_base="$(basename "$_rel")"
		_src="$_prefix/lib/$_base"
		[ -f "$_src" ] || { echo "build-arm64.sh: missing $_src (brew install ${_rel%%/*})" >&2; exit 1; }
		ln -sf "$_src" "$STATICONLY/$_base"
	done
	# libpng's own archive is libpng16.a; alephone's SDL_TTF_LIBS below links
	# it as -lpng.
	ln -sf "$(brew --prefix libpng)/lib/libpng16.a" "$STATICONLY/libpng.a"
}

ensure_arm64_deps

# ---------------------------------------------------------------------------
# Build in an isolated tree, not the shared working directory. Two sessions
# can be in this repo at once (CLAUDE.md: "Nothing arbitrates WORKING
# TREES"); an in-place `./configure && make` would drop generated files
# (Makefile, config.status, *.o) into a tree another session may be editing.
# Same isolation ppc/x86_64 get from rsync'ing to a separate directory on the
# remote build host -- this is the local equivalent.
BUILD_DIR="$HOME/alephone-build-arm64"
echo "[build-arm64] syncing source tree to $BUILD_DIR..."
mkdir -p "$BUILD_DIR"
rsync -az --delete $(source_stamp_rsync_excludes "$SOURCE_STAMP_EXCLUDES") \
	"$REPO_ROOT/" "$BUILD_DIR/"
_stamp_arm64="$(source_stamp_compute "$REPO_ROOT" "$SOURCE_STAMP_EXCLUDES")"

cd "$BUILD_DIR"

# Same mtime-ordering fix build.sh's ppc/x86_64 branches use: rsync does not
# preserve autotools' dependency-order mtimes, so maintainer-mode rules can
# decide configure.ac is newer than the generated configure/Makefile.in and
# try to regenerate them with tools this run doesn't need.
touch -t 202001010000 configure.ac acinclude.m4 $(find . -name '*.m4' -not -name aclocal.m4) $(find . -name Makefile.am)
touch -t 202001020000 aclocal.m4
touch -t 202001030000 configure config.h.in $(find . -name Makefile.in)

export CC=clang
export CXX=clang++
export OBJCXX=clang++
# Deliberately restrictive, not the Homebrew default: prevents configure from
# silently auto-detecting whatever else happens to be installed system-wide
# (this bit once already, mid-development -- libvorbis/libpng got picked up
# uninvited via the default pkg-config path, each pulling in an absolute
# /opt/homebrew/... dylib reference, the exact class of bug alephone#5 fixed
# once already for x86_64/SDL2). Only the packages this port actually wants
# are reachable via pkg-config at all.
export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig:$SDL_DIR/lib/pkgconfig"

COMMON_CFLAGS="-O2 -mmacosx-version-min=$VMIN"
COMMON_CXXFLAGS="-O2 -std=c++17 -mmacosx-version-min=$VMIN"
# -lc++ unconditionally: AX_BOOST_FILESYSTEM's own probe (not the
# BOOST_FILESYSTEM_LIB override below) briefly puts the static
# libboost_filesystem.a on the link line for later plain-C AC_CHECK_FUNCS
# tests (e.g. snprintf); without libc++ already on LDFLAGS those C-mode
# links fail on undefined C++ runtime symbols.
COMMON_LDFLAGS="-mmacosx-version-min=$VMIN -L$STATICONLY -L$DEPS/lib -L$SDL_DIR/lib -L$BOOST/lib -lc++ -lobjc -framework Cocoa -framework CoreFoundation -framework ApplicationServices -framework AudioToolbox -framework AudioUnit -framework CoreAudio -framework Carbon -framework IOKit -Wl,-w"
COMMON_CPPFLAGS="-I$DEPS/include -I$SDL_DIR/include -I$SDL_DIR/include/SDL2 -I$ASIO/include -I$FREETYPE/include/freetype2 -I$BOOST/include"

echo "[configure] configuring alephone for arm64-apple-darwin (native)..."
./configure \
    --without-vpx --without-matroska --without-ebml --without-libyuv --without-nfd \
    --without-curl --without-zzip --without-miniupnpc --without-sdl_image --disable-steam --without-catch2 \
    --without-vorbis --without-vorbisenc --without-png \
    --with-boost="$BOOST" \
    --with-boost-libdir="$STATICONLY" \
    CC="$CC" CXX="$CXX" OBJCXX="$OBJCXX" \
    CFLAGS="$COMMON_CFLAGS" \
    CXXFLAGS="$COMMON_CXXFLAGS" \
    OBJCXXFLAGS="$COMMON_CXXFLAGS" \
    CPPFLAGS="$COMMON_CPPFLAGS" \
    LDFLAGS="$COMMON_LDFLAGS" \
    BOOST_CPPFLAGS="-I$BOOST/include" \
    SDL_CFLAGS="-I$SDL_DIR/include -I$SDL_DIR/include/SDL2 -D_THREAD_SAFE" \
    SDL_LIBS="-L$SDL_DIR/lib -lSDL2 -lobjc -framework Cocoa -framework Carbon -framework IOKit -framework CoreAudio -framework AudioToolbox -framework AudioUnit" \
    SDL_TTF_CFLAGS="-I$DEPS/include -I$DEPS/include/SDL2 -I$FREETYPE/include/freetype2 -D_THREAD_SAFE" \
    SDL_TTF_LIBS="-L$DEPS/lib -lSDL2_ttf -L$STATICONLY -lfreetype -lpng -lbz2" \
    ZLIB_CFLAGS="" \
    ZLIB_LIBS="-lz" \
    SNDFILE_CFLAGS="-I$SNDFILE/include" \
    SNDFILE_LIBS="-L$STATICONLY -lsndfile -lFLAC -lvorbis -lvorbisenc -logg -lopus -lmpg123 -lmp3lame" \
    OPENAL_CFLAGS="-I$DEPS/include -I$DEPS/include/AL" \
    OPENAL_LIBS="-L$DEPS/lib -lopenal" \
    > /tmp/alephone_arm64_config.log 2>&1 || { tail -60 /tmp/alephone_arm64_config.log; exit 1; }

echo "[build] running make -j$(sysctl -n hw.ncpu)..."
make -j"$(sysctl -n hw.ncpu)" > /tmp/alephone_arm64_build.log 2>&1 || { tail -60 /tmp/alephone_arm64_build.log; exit 1; }

echo "[build] arm64 slice build succeeded: $(ls -la Source_Files/alephone)"

# install_name_tool retarget happens HERE, on the thin arm64-only slice,
# before lipo -- same reason x86_64 does it in build.sh: Apple's current
# install_name_tool cannot parse the PPC cross-compiled slice's load
# commands once it's part of a fat file ("malformed load command 0"), and a
# fat file containing arm64 has its own version of this problem the other
# direction (old-mac-build-host docs/apple-silicon-arm64.md: otool/
# install_name_tool on Lion choke on any fat file with an arm64 member,
# understood only by lipo, which just copies slices around blind). Editing
# on the thin, single-arch file sidesteps both.
install_name_tool -change "$SDL_DIR/lib/libSDL2-2.0.0.dylib" \
	@executable_path/../Frameworks/libSDL2-2.0.0.dylib \
	Source_Files/alephone

# arm64 binaries are KERN_KILLED at exec if unsigned or mis-signed -- fatal,
# not cosmetic, unlike ppc/x86_64 where an unsigned binary merely triggers a
# Gatekeeper prompt. Ad-hoc sign now; package-dmg.sh's later `codesign
# --force --deep` on the whole .app re-signs every slice anyway, but a slice
# that cannot even be verified here would be a much more confusing failure
# to chase after lipo.
codesign --force --sign - Source_Files/alephone
codesign --verify --verbose=1 Source_Files/alephone

GOT="$(lipo -archs Source_Files/alephone)"
[ "$GOT" = "arm64" ] || { echo "[build-arm64] expected arm64, got '$GOT'" >&2; exit 1; }

mkdir -p "$REPO_ROOT/build" "$REPO_ROOT/build/deps-arm64"
rsync -a Source_Files/alephone "$REPO_ROOT/build/alephone-arm64"
rsync -a "$SDL_DIR/lib/libSDL2-2.0.0.dylib" "$REPO_ROOT/build/deps-arm64/libSDL2-2.0.0.dylib"
echo "[build] fetched build/alephone-arm64 and build/deps-arm64/libSDL2-2.0.0.dylib"
otool -hv "$REPO_ROOT/build/alephone-arm64"

# Written LAST, after the codesign/lipo assertions above, so a slice that
# failed either leaves no stamp -- matching source-stamp.sh's own documented
# ordering requirement (a driver that mutates/produces output must stamp
# after, not before, or a failed build can still read as fresh).
mkdir -p "$REPO_ROOT/build/stamp-arm64"
source_stamp_write "$REPO_ROOT/build/stamp-arm64" "$_stamp_arm64"

echo "[build] DONE: build/alephone-arm64"
