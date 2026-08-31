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
		# Stamp what was actually rsynced (source_stamp_compute matches the
		# same exclude list the rsync above used), so `fat` below can tell
		# a fresh slice from a stale one instead of always rebuilding.
		_stamp_ppc="$(source_stamp_compute "$REPO_ROOT" "$SOURCE_STAMP_EXCLUDES")"

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
# -Wl,-unexported_symbols_list,<libstdc++/__gnu_cxx/__cxxabiv1 deny-list>:
# alephone#11, 2026-08-29. First attempt here was -exported_symbols_list
# (an ALLOW-list of just _main) -- fixed Leopard's cross-image weak-bind
# collision (below) but hid EVERYTHING not _main, collateral damage that
# crashed real Tiger (mini-g4) 100% of the time at startup, before any
# application code ran: EXC_BAD_ACCESS/KERN_PROTECTION_FAILURE at 0x0 in
# libSystem's _malloc_initialize, via dyld's imageNotification ->
# __keymgr_dwarf2_register_sections chain -- Tiger's old dyld (46.16) needs
# some libgcc.a/runtime-support symbol visible for that DWARF-unwind
# registration handshake that the blanket list also hid. Reverted, replaced
# with a DENY-list (scripts/ppc-libstdcxx-unexport-list.txt): hides only the
# actual collision surface (libstdc++.a's std::/__gnu_cxx::/__cxxabiv1::
# namespaces plus global operator new/delete), leaves libgcc.a and
# everything else exported exactly as before. Verified real hardware both
# directions: Leopard (imac-g5) 0 cross-image libstdc++.6.dylib lazy binds
# (down from 188 with no export restriction at all), Tiger (mini-g4) clean
# launch, no crash-reporter entry. Panther not independently verified.
# The list is a nm(1)-generated snapshot of the linked libstdc++/libgcc
# symbol set at the time it was made -- regenerate it (see the file's own
# header comment for the exact nm/awk recipe) if COMMON_LDFLAGS, the
# toolchain, or libstdc++.a's version ever changes, and re-verify with a
# real DYLD_PRINT_BINDINGS trace after regenerating, not just a rebuild --
# this took multiple rounds to reach zero cross-image binds even with the
# recipe below (Itanium name-mangling gotchas: nm -m's linkage-annotation
# field shifts by one word for "weak external" vs "external", and some
# real collision symbols have no textual std:: prefix at all -- global
# operator new/delete and the Itanium ABI's single-letter substitution
# abbreviations for the most common std types, e.g. _ZTVSi for "vtable for
# std::istream").
COMMON_LDFLAGS="-mmacosx-version-min=10.3 -isysroot $SDK -L$DEPS/lib -L$SDL_DIR/lib -static-libstdc++ -static-libgcc -Wl,-force_load,$TOOLCHAIN/powerpc-apple-darwin8/lib/libstdc++.a -Wl,-force_load,$TOOLCHAIN/lib/gcc/powerpc-apple-darwin8/14.2.0/libgcc.a -Wl,-unexported_symbols_list,$(pwd)/scripts/ppc-libstdcxx-unexport-list.txt -lobjc -framework Cocoa -framework CoreFoundation -framework ApplicationServices -framework AudioToolbox -framework AudioUnit -framework CoreAudio -framework Carbon -framework IOKit -framework AGL -framework OpenGL -Wl,-w"
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
		mkdir -p "$REPO_ROOT/build/stamp-ppc"
		source_stamp_write "$REPO_ROOT/build/stamp-ppc" "$_stamp_ppc"
		;;

	x86_64)
		echo "[build] syncing source tree to $BUILD_HOST..."
		ssh "$BUILD_HOST" 'mkdir -p ~/alephone-build-x86_64'
		rsync -az --delete $(source_stamp_rsync_excludes "$SOURCE_STAMP_EXCLUDES") \
			"$REPO_ROOT/" "$BUILD_HOST:~/alephone-build-x86_64/"
		# See ppc branch above: stamp what was actually rsynced.
		_stamp_x86_64="$(source_stamp_compute "$REPO_ROOT" "$SOURCE_STAMP_EXCLUDES")"

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
		mkdir -p "$REPO_ROOT/build/stamp-x86_64"
		source_stamp_write "$REPO_ROOT/build/stamp-x86_64" "$_stamp_x86_64"
		;;

	fat)
		# Only rebuild a slice if its recorded source stamp doesn't match the
		# current tree -- content hash (source_stamp.sh), not mtime, matching
		# the same freshness check the rest of the fleet uses; see that
		# file's header for why mtime/existence checks were rejected. Without
		# this, `fat` unconditionally rebuilds both slices from scratch every
		# time even when they were just built moments ago (measured
		# 2026-08-29: ~26min wasted re-running ppc+x86_64 that were already
		# current).
		_stamp_now="$(source_stamp_compute "$REPO_ROOT" "$SOURCE_STAMP_EXCLUDES")"
		if [ -f "$REPO_ROOT/build/alephone-ppc" ] && source_stamp_verify "$REPO_ROOT/build/stamp-ppc" "$_stamp_now"; then
			echo "[fat] ppc slice already current (source stamp match), skipping rebuild"
		else
			"$0" ppc
		fi
		if [ -f "$REPO_ROOT/build/alephone-x86_64" ] && source_stamp_verify "$REPO_ROOT/build/stamp-x86_64" "$_stamp_now"; then
			echo "[fat] x86_64 slice already current (source stamp match), skipping rebuild"
		else
			"$0" x86_64
		fi

		# arm64 (alephone#17) is OPTIONAL here, not required, matching the
		# shape every other port in this fleet already uses for it
		# (old-mac-build-host docs/apple-silicon-arm64.md: "every one of the
		# three fuses treats its arm64 slice as OPTIONAL, so a slice that
		# failed to arrive does not stop a release"). It can only be BUILT on
		# an actual Apple Silicon Mac (scripts/build-arm64.sh checks
		# `uname -m` itself and refuses otherwise) -- this workstation is the
		# only one in the fleet, but `fat` should still produce a working
		# ppc+x86_64 binary if run somewhere that isn't it, rather than fail
		# outright over a slice nothing there can ever build.
		if [ "$(uname -m)" = "arm64" ]; then
			if [ -f "$REPO_ROOT/build/alephone-arm64" ] && source_stamp_verify "$REPO_ROOT/build/stamp-arm64" "$_stamp_now"; then
				echo "[fat] arm64 slice already current (source stamp match), skipping rebuild"
			else
				"$REPO_ROOT/scripts/build-arm64.sh"
			fi
		elif [ -f "$REPO_ROOT/build/alephone-arm64" ]; then
			# Staged in from elsewhere (e.g. copied off the workstation).
			# Freshness can't be proven on a machine that can't recompute
			# what it should hash against -- see source-stamp.sh's own
			# "slice that can go stale" warning -- so this is used as-is,
			# loudly, rather than silently trusted or silently dropped.
			echo "[fat] arm64 slice present but this is not an arm64 machine -- using it as-is, staleness NOT verified"
		else
			echo "[fat] no arm64 slice and this is not an arm64 machine -- building ppc+x86_64 only"
		fi

		echo "[fat] creating Universal fat binary..."
		_fat_inputs="$REPO_ROOT/build/alephone-ppc $REPO_ROOT/build/alephone-x86_64"
		_fat_slices="ppc x86_64"
		if [ -f "$REPO_ROOT/build/alephone-arm64" ]; then
			_fat_inputs="$_fat_inputs $REPO_ROOT/build/alephone-arm64"
			_fat_slices="$_fat_slices arm64"
		fi
		echo "[fat] slices included: $_fat_slices"
		lipo -create -output "$REPO_ROOT/build/alephone" $_fat_inputs
		echo "[fat] Universal binary created at build/alephone:"
		lipo -info "$REPO_ROOT/build/alephone"

		# ppc statically links SDL2; x86_64 and arm64 both bundle it as a
		# dylib (see build.sh's x86_64 branch and build-arm64.sh), each
		# already retargeted to the SAME install name
		# (@executable_path/../Frameworks/libSDL2-2.0.0.dylib) on their own
		# thin slice. Fuse the two into ONE universal dylib rather than
		# shipping two files under one name -- dyld picks the right slice
		# out of a fat dylib automatically, same as it does for the app
		# binary itself, and package-dmg.sh only has one Frameworks/ entry
		# to bundle either way.
		if [ -f "$REPO_ROOT/build/deps-arm64/libSDL2-2.0.0.dylib" ]; then
			mkdir -p "$REPO_ROOT/build/deps-fat"
			lipo -create -output "$REPO_ROOT/build/deps-fat/libSDL2-2.0.0.dylib" \
				"$REPO_ROOT/build/deps-x86_64/libSDL2-2.0.0.dylib" \
				"$REPO_ROOT/build/deps-arm64/libSDL2-2.0.0.dylib"
			echo "[fat] fused universal SDL2 dylib at build/deps-fat/libSDL2-2.0.0.dylib:"
			lipo -info "$REPO_ROOT/build/deps-fat/libSDL2-2.0.0.dylib"
		fi
		;;

	*)
		echo "Target $TARGET not implemented yet (want ppc, x86_64, or fat)"
		exit 1
		;;
esac

echo "[build] DONE: build/alephone-$TARGET"
