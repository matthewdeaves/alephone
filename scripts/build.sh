#!/usr/bin/env bash
# build.sh - Build Aleph One for a specific target slice (ppc, i386, x86_64)
# usage: scripts/build.sh <ppc|i386|x86_64>
# output: build/alephone-<target>

set -euo pipefail

TARGET="${1:?usage: $0 <ppc|i386|x86_64>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

. "$REPO_ROOT/scripts/source-stamp.sh"
. "$REPO_ROOT/scripts/source-stamp-excludes.sh"

BUILD_HOST_CLAIMED=0
if [ "$TARGET" = "ppc" ] || [ "$TARGET" = "x86_64" ]; then
	if [ -z "${BUILD_HOST:-}" ]; then
		export BENCH_LOCK_CLAIM="${BENCH_LOCK_CLAIM:-$$.$(date +%s).${RANDOM:-0}}"
		BUILD_HOST="$(BUILD_LOCK_WAIT="${BUILD_LOCK_WAIT:-900}" \
			"$REPO_ROOT/scripts/pick-build-host.sh" --acquire "alephone build.sh $TARGET")" || {
			echo "build.sh: no free Intel build host; see scripts/pick-build-host.sh --status" >&2
			exit 1
		}
		BUILD_HOST_CLAIMED=1
		echo "[build] claimed build host: $BUILD_HOST"
	fi
	trap '[ "$BUILD_HOST_CLAIMED" = 1 ] && "$REPO_ROOT/scripts/pick-build-host.sh" --release "$BUILD_HOST" >/dev/null 2>&1; true' EXIT
fi

mkdir -p "$REPO_ROOT/build"

case "$TARGET" in
	ppc)
		echo "[build] syncing source tree to $BUILD_HOST..."
		ssh "$BUILD_HOST" 'mkdir -p ~/alephone-build-ppc'
		rsync -az --delete $(source_stamp_rsync_excludes "$SOURCE_STAMP_EXCLUDES") \
			"$REPO_ROOT/" "$BUILD_HOST:~/alephone-build-ppc/"

		echo "[build] compiling Aleph One PPC slice on $BUILD_HOST..."
		ssh "$BUILD_HOST" 'bash -s' << 'REMOTE_BUILD'
set -euo pipefail

cd ~/alephone-build-ppc

# rsync does not preserve autotools' dependency-order mtimes, so the
# maintainer-mode rules in Makefile.in can decide configure.ac is newer than
# aclocal.m4/configure/Makefile.in and try to regenerate them with tools this
# build host doesn't have (e.g. aclocal-1.18). Force pre-generated-tree order.
touch -t 202001010000 configure.ac acinclude.m4 $(find . -name '*.m4' -not -name aclocal.m4) $(find . -name Makefile.am)
touch -t 202001020000 aclocal.m4
touch -t 202001030000 configure config.h.in $(find . -name Makefile.in)

DEPS=/Users/mini/alephone-ppc-deps
TOOLCHAIN=/Users/mini/gcc14-ppc
# Host-conditional SDK path (old-mac-build-host#47): imac-2019 runs a sealed
# system volume (csrutil enabled) -- /Developer can never exist there, real
# SDKs live at ~/SDKs instead. Detect by existence, not hostname, so this
# runs correctly inside the quoted heredoc without plumbing $BUILD_HOST
# through ssh.
if [ -d /Developer/SDKs/MacOSX10.3.9.sdk ]; then
	SDK=/Developer/SDKs/MacOSX10.3.9.sdk
elif [ -d ~/SDKs/MacOSX10.3.9.sdk ]; then
	SDK=~/SDKs/MacOSX10.3.9.sdk
else
	echo "build.sh: no MacOSX10.3.9 SDK found (checked /Developer/SDKs and ~/SDKs)" >&2
	exit 1
fi
SDL_DIR=/Users/mini/oldmac/sdl2-ppc-tiger103
[ -d "$SDL_DIR" ] || SDL_DIR=/Users/mini/oldmac/sdl2-ppc-panther

# Ensure SDL2 headers accessible as <SDL2/SDL.h> and <SDL.h>
ln -sf "$SDL_DIR/include/SDL2" "$DEPS/include/SDL2"
cp "$DEPS/include/SDL_ttf.h" "$DEPS/include/SDL2/" 2>/dev/null || true

export CC="$TOOLCHAIN/bin/powerpc-apple-darwin8-gcc"
export CXX="$TOOLCHAIN/bin/powerpc-apple-darwin8-g++"
export OBJCXX="$TOOLCHAIN/bin/powerpc-apple-darwin8-g++"
export AR="$TOOLCHAIN/bin/powerpc-apple-darwin8-ar"
export RANLIB="$TOOLCHAIN/bin/powerpc-apple-darwin8-ranlib"
export PATH="/Users/mini/local/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig:$SDL_DIR/lib/pkgconfig"

COMMON_CFLAGS="-O2 -mmacosx-version-min=10.3 -isysroot $SDK -include stddef.h"
COMMON_CXXFLAGS="-O2 -std=c++17 -mmacosx-version-min=10.3 -isysroot $SDK -include stddef.h"
# -Wl,-force_load,<libstdc++.a/libgcc.a>: alephone#11, 2026-08-28. -static-libstdc++
# -static-libgcc alone were not enough -- measured on real Leopard/PPC hardware
# (imac-g5): calls like std::basic_istream<char>::operator>>(short&) (an
# out-of-line libstdc++ symbol, not header-inline template code) were still
# resolving into the SYSTEM's /usr/lib/libstdc++.6.dylib instead of our
# statically-linked copy -- confirmed via the live crash reporter's Binary
# Images list, PC landed inside that dylib's mapped range. Root cause: Leopard's
# own AudioToolbox/CoreAudio/OpenGL frameworks (all three, all required) each
# transitively link libstdc++.6.dylib themselves, and this toolchain's linker
# apparently satisfies some libstdc++ symbol references from that reachable
# dynamic re-export rather than pulling them from the static archive, even
# with -static-libstdc++ set. Two ABI-incompatible libstdc++s' RTTI/locale
# facet objects meeting across that boundary is an indirect call through a
# bad vtable pointer -- EXC_BAD_INSTRUCTION, exactly what got hit. -force_load
# makes every object in the given archive part of THIS binary unconditionally,
# so there is no longer an unresolved reference for the wrong dylib to satisfy.
COMMON_LDFLAGS="-mmacosx-version-min=10.3 -isysroot $SDK -L$DEPS/lib -L$SDL_DIR/lib -static-libstdc++ -static-libgcc -Wl,-force_load,$TOOLCHAIN/powerpc-apple-darwin8/lib/libstdc++.a -Wl,-force_load,$TOOLCHAIN/lib/gcc/powerpc-apple-darwin8/14.2.0/libgcc.a -lobjc -framework Cocoa -framework CoreFoundation -framework ApplicationServices -framework AudioToolbox -framework AudioUnit -framework CoreAudio -framework Carbon -framework IOKit -framework AGL -framework OpenGL -Wl,-w"
COMMON_CPPFLAGS="-I$DEPS/include -I$SDL_DIR/include -I$SDL_DIR/include/SDL2 -I$DEPS/include/freetype2 -isysroot $SDK -include stddef.h"

echo "[configure] configuring alephone for powerpc-apple-darwin8..."
./configure \
    --host=powerpc-apple-darwin8 \
    --without-vpx --without-matroska --without-ebml --without-libyuv --without-nfd \
    --without-curl --without-zzip --without-miniupnpc --without-sdl_image --disable-steam --without-catch2 \
    --with-boost="$DEPS" \
    --with-boost-libdir="$DEPS/lib" \
    CC="$CC" CXX="$CXX" OBJCXX="$OBJCXX" \
    CFLAGS="$COMMON_CFLAGS" \
    CXXFLAGS="$COMMON_CXXFLAGS" \
    OBJCXXFLAGS="$COMMON_CXXFLAGS" \
    CPPFLAGS="$COMMON_CPPFLAGS" \
    LDFLAGS="$COMMON_LDFLAGS" \
    BOOST_FILESYSTEM_LIB="$DEPS/lib/libboost_filesystem.a $DEPS/lib/libboost_system.a" \
    BOOST_CPPFLAGS="-I$DEPS/include" \
    SDL_CFLAGS="-I$SDL_DIR/include -I$SDL_DIR/include/SDL2 -D_THREAD_SAFE" \
    SDL_LIBS="-L$SDL_DIR/lib -lSDL2 -lobjc -framework Cocoa -framework Carbon -framework IOKit -framework CoreAudio -framework AudioToolbox -framework AudioUnit" \
    SDL_TTF_CFLAGS="-I$DEPS/include -I$DEPS/include/SDL2 -I$DEPS/include/freetype2 -D_THREAD_SAFE" \
    SDL_TTF_LIBS="-L$DEPS/lib -lSDL2_ttf -lfreetype" \
    ZLIB_CFLAGS="-I$SDK/usr/include" \
    ZLIB_LIBS="-L$SDK/usr/lib -lz" \
    SNDFILE_CFLAGS="-I$DEPS/include" \
    SNDFILE_LIBS="-L$DEPS/lib -lsndfile" \
    OPENAL_CFLAGS="-I$DEPS/include -I$DEPS/include/AL" \
    OPENAL_LIBS="-L$DEPS/lib -lopenal" \
    > /tmp/alephone_ppc_config.log 2>&1 || { tail -50 /tmp/alephone_ppc_config.log; exit 1; }

echo "[build] running make -j2..."
make -j2 > /tmp/alephone_ppc_build.log 2>&1 || { tail -50 /tmp/alephone_ppc_build.log; exit 1; }

echo "[build] PPC slice build succeeded: $(ls -la Source_Files/alephone)"
REMOTE_BUILD

		rsync -az "$BUILD_HOST:~/alephone-build-ppc/Source_Files/alephone" "$REPO_ROOT/build/alephone-ppc"
		echo "[build] fetched build/alephone-ppc"
		otool -hv "$REPO_ROOT/build/alephone-ppc"
		;;

	x86_64)
		echo "[build] syncing source tree to $BUILD_HOST..."
		ssh "$BUILD_HOST" 'mkdir -p ~/alephone-build-x86_64'
		rsync -az --delete $(source_stamp_rsync_excludes "$SOURCE_STAMP_EXCLUDES") \
			"$REPO_ROOT/" "$BUILD_HOST:~/alephone-build-x86_64/"

		echo "[build] compiling Aleph One x86_64 slice on $BUILD_HOST..."
		ssh "$BUILD_HOST" 'bash -s' << 'REMOTE_BUILD'
set -euo pipefail

cd ~/alephone-build-x86_64

# See ppc branch above: force pre-generated-tree mtime order so maintainer-mode
# rules don't try to regenerate aclocal.m4/configure/Makefile.in with tools
# this build host doesn't have.
touch -t 202001010000 configure.ac acinclude.m4 $(find . -name '*.m4' -not -name aclocal.m4) $(find . -name Makefile.am)
touch -t 202001020000 aclocal.m4
touch -t 202001030000 configure config.h.in $(find . -name Makefile.in)

DEPS=/Users/mini/alephone-intel-deps
TOOLCHAIN=/Users/mini/gcc14-ppc-build/tools/gcc-7.5.0-host
SDL_DIR=/Users/mini/oldmac/sdl2-x86_64

# Ensure SDL2 headers accessible as <SDL2/SDL.h> and <SDL.h>
ln -sf "$SDL_DIR/include/SDL2" "$DEPS/include/SDL2"
cp "$DEPS/include/SDL2/SDL_ttf.h" "$DEPS/include/" 2>/dev/null || true

export CC="$TOOLCHAIN/bin/gcc-7"
export CXX="$TOOLCHAIN/bin/g++-7"
export OBJCXX="$TOOLCHAIN/bin/g++-7"
export AR="/usr/bin/ar"
export RANLIB="/usr/bin/ranlib"
export PATH="/Users/mini/local/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig:$SDL_DIR/lib/pkgconfig"

COMMON_CFLAGS="-O2 -mmacosx-version-min=10.6"
COMMON_CXXFLAGS="-O2 -std=c++17 -mmacosx-version-min=10.6"
COMMON_LDFLAGS="-mmacosx-version-min=10.6 -L$DEPS/lib -L$SDL_DIR/lib -static-libstdc++ -static-libgcc -lobjc -framework Cocoa -framework CoreFoundation -framework ApplicationServices -framework AudioToolbox -framework AudioUnit -framework CoreAudio -framework Carbon -framework IOKit -Wl,-w"
COMMON_CPPFLAGS="-I$DEPS/include -I$SDL_DIR/include -I$SDL_DIR/include/SDL2 -I$DEPS/include/freetype2"

echo "[configure] configuring alephone for x86_64-apple-darwin..."
./configure \
    --host=x86_64-apple-darwin \
    --without-vpx --without-matroska --without-ebml --without-libyuv --without-nfd \
    --without-curl --without-zzip --without-miniupnpc --without-sdl_image --disable-steam --without-catch2 \
    --with-boost="$DEPS" \
    --with-boost-libdir="$DEPS/lib" \
    CC="$CC" CXX="$CXX" OBJCXX="$OBJCXX" \
    CFLAGS="$COMMON_CFLAGS" \
    CXXFLAGS="$COMMON_CXXFLAGS" \
    OBJCXXFLAGS="$COMMON_CXXFLAGS" \
    CPPFLAGS="$COMMON_CPPFLAGS" \
    LDFLAGS="$COMMON_LDFLAGS" \
    BOOST_FILESYSTEM_LIB="$DEPS/lib/libboost_filesystem.a $DEPS/lib/libboost_system.a" \
    BOOST_CPPFLAGS="-I$DEPS/include" \
    SDL_CFLAGS="-I$SDL_DIR/include -I$SDL_DIR/include/SDL2 -D_THREAD_SAFE" \
    SDL_LIBS="-L$SDL_DIR/lib -lSDL2 -lobjc -framework Cocoa -framework Carbon -framework IOKit -framework CoreAudio -framework AudioToolbox -framework AudioUnit" \
    SDL_TTF_CFLAGS="-I$DEPS/include -I$DEPS/include/SDL2 -I$DEPS/include/freetype2 -D_THREAD_SAFE" \
    SDL_TTF_LIBS="-L$DEPS/lib -lSDL2_ttf -lfreetype" \
    ZLIB_CFLAGS="-I/usr/include" \
    ZLIB_LIBS="-lz" \
    SNDFILE_CFLAGS="-I$DEPS/include" \
    SNDFILE_LIBS="-L$DEPS/lib -lsndfile" \
    OPENAL_CFLAGS="-I$DEPS/include -I$DEPS/include/AL" \
    OPENAL_LIBS="-L$DEPS/lib -lopenal" \
    > /tmp/alephone_intel_config.log 2>&1 || { tail -50 /tmp/alephone_intel_config.log; exit 1; }

echo "[build] running make -j2..."
make -j2 > /tmp/alephone_intel_build.log 2>&1 || { tail -50 /tmp/alephone_intel_build.log; exit 1; }

echo "[build] x86_64 slice build succeeded: $(ls -la Source_Files/alephone)"
REMOTE_BUILD

		rsync -az "$BUILD_HOST:~/alephone-build-x86_64/Source_Files/alephone" "$REPO_ROOT/build/alephone-x86_64"
		echo "[build] fetched build/alephone-x86_64"
		otool -hv "$REPO_ROOT/build/alephone-x86_64"

		# SDL2 is the one dependency of the 6 in legacy-mac-hardware.md that is
		# NOT statically linked on x86_64 (everything else -- SDL2_ttf, boost,
		# asio, libsndfile, openal-soft -- builds --enable-static per
		# build-deps-intel.sh). It links against $SDL_DIR/lib on the build
		# host as a bare absolute path, which only exists on machines that
		# happen to share that exact filesystem layout -- measured 2026-08-28
		# (alephone#5): a fresh x86_64 build crashed at launch on imac-2019
		# with `Library not loaded: /Users/mini/oldmac/sdl2-x86_64/lib/
		# libSDL2-2.0.0.dylib`, dyld "Library missing". Fetch the actual
		# dylib alongside the binary so package-dmg.sh can bundle it into
		# each app's Contents/Frameworks and retarget the load command to
		# @executable_path -- the same self-contained shape quakespasm ships
		# SDL.framework in, not a fixed host path.
		mkdir -p "$REPO_ROOT/build/deps-x86_64"
		scp -q "$BUILD_HOST:/Users/mini/oldmac/sdl2-x86_64/lib/libSDL2-2.0.0.dylib" \
			"$REPO_ROOT/build/deps-x86_64/libSDL2-2.0.0.dylib"
		echo "[build] fetched build/deps-x86_64/libSDL2-2.0.0.dylib"

		# Retarget on the THIN x86_64 slice, before lipo -- not later, on the
		# fat binary, in package-dmg.sh. Apple's current install_name_tool
		# cannot parse the PPC cross-compiled slice's load commands at all
		# ("malformed load command 0 (cmdsize is zero)", measured 2026-08-28)
		# and aborts on the whole fat file once ppc is lipo'd in.
		install_name_tool -change /Users/mini/oldmac/sdl2-x86_64/lib/libSDL2-2.0.0.dylib \
			@executable_path/../Frameworks/libSDL2-2.0.0.dylib \
			"$REPO_ROOT/build/alephone-x86_64"
		echo "[build] retargeted libSDL2 load command to @executable_path"
		;;

	fat)
		"$0" ppc
		"$0" x86_64
		echo "[fat] creating Universal fat binary..."
		lipo -create -output "$REPO_ROOT/build/alephone" \
			"$REPO_ROOT/build/alephone-ppc" \
			"$REPO_ROOT/build/alephone-x86_64"
		echo "[fat] Universal binary created at build/alephone:"
		lipo -info "$REPO_ROOT/build/alephone"
		;;

	*)
		echo "Target $TARGET not implemented yet (want ppc, x86_64, or fat)"
		exit 1
		;;
esac

echo "[build] DONE: build/alephone-$TARGET"
