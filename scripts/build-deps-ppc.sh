#!/usr/bin/env bash
# build-deps-ppc.sh - Stage and cross-compile PPC dependencies on mini-intel
# Target: powerpc-apple-darwin8, sysroot: MacOSX10.3.9.sdk
# Toolchain: /Users/mini/gcc14-ppc
# Output prefix: /Users/mini/alephone-ppc-deps

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Claim build host
BUILD_HOST_CLAIMED=0
if [ -z "${BUILD_HOST:-}" ]; then
	export BENCH_LOCK_CLAIM="${BENCH_LOCK_CLAIM:-$$.$(date +%s).${RANDOM:-0}}"
	BUILD_HOST="$(BUILD_LOCK_WAIT="${BUILD_LOCK_WAIT:-900}" \
		"$REPO_ROOT/scripts/pick-build-host.sh" --acquire "alephone build-deps-ppc")" || {
		echo "build-deps-ppc.sh: no free Intel build host; see scripts/pick-build-host.sh --status" >&2
		exit 1
	}
	BUILD_HOST_CLAIMED=1
	echo "[deps-ppc] claimed build host: $BUILD_HOST"
fi
trap '[ "$BUILD_HOST_CLAIMED" = 1 ] && "$REPO_ROOT/scripts/pick-build-host.sh" --release "$BUILD_HOST" >/dev/null 2>&1; true' EXIT

echo "[deps-ppc] syncing source archives to $BUILD_HOST..."
ssh "$BUILD_HOST" 'mkdir -p ~/alephone-deps-src ~/alephone-ppc-deps'
rsync -az "$REPO_ROOT/.deps/" "$BUILD_HOST:~/alephone-deps-src/"
scp -q "$REPO_ROOT/scripts/patches/boost-1.76.0-less_nocase-no-locale.patch" \
	"$BUILD_HOST:/tmp/boost-1.76.0-less_nocase-no-locale.patch"

echo "[deps-ppc] running cross-compilation on $BUILD_HOST..."
ssh "$BUILD_HOST" 'bash -s' << 'REMOTE_SCRIPT'
set -euo pipefail

SRC=~/alephone-deps-src
BUILD=~/alephone-deps-build
PREFIX=~/alephone-ppc-deps
TOOLCHAIN=/Users/mini/gcc14-ppc
SDK=/Developer/SDKs/MacOSX10.3.9.sdk
JOBS=2

SDL_PREFIX=/Users/mini/oldmac/sdl2-ppc-tiger103
[ -d "$SDL_PREFIX" ] || SDL_PREFIX=/Users/mini/oldmac/sdl2-ppc-panther

TAR=tar
[ -x /Users/mini/local/bin/gtar ] && TAR=/Users/mini/local/bin/gtar

export CC="$TOOLCHAIN/bin/powerpc-apple-darwin8-gcc"
export CXX="$TOOLCHAIN/bin/powerpc-apple-darwin8-g++"
export AR="$TOOLCHAIN/bin/powerpc-apple-darwin8-ar"
export RANLIB="$TOOLCHAIN/bin/powerpc-apple-darwin8-ranlib"
export PATH="/Users/mini/local/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$SDL_PREFIX/lib/pkgconfig"

COMMON_CFLAGS="-O2 -mmacosx-version-min=10.3 -isysroot $SDK -include stddef.h"
COMMON_CXXFLAGS="-O2 -std=c++17 -mmacosx-version-min=10.3 -isysroot $SDK -include stddef.h"
COMMON_LDFLAGS="-mmacosx-version-min=10.3 -isysroot $SDK -L$PREFIX/lib"
COMMON_CPPFLAGS="-isysroot $SDK -I$PREFIX/include"

mkdir -p "$BUILD" "$PREFIX/include" "$PREFIX/lib" "$PREFIX/lib/pkgconfig"

# -------------------------------------------------------------
# 1. FreeType 2.12.1
# -------------------------------------------------------------
if [ ! -f "$PREFIX/lib/libfreetype.a" ]; then
    echo "[1/6] Building FreeType 2.12.1..."
    cd "$BUILD"
    rm -rf freetype-2.12.1
    $TAR -xzf "$SRC/freetype-2.12.1.tar.gz"
    cd freetype-2.12.1
    ./configure --host=powerpc-apple-darwin8 \
        --prefix="$PREFIX" \
        --disable-shared --enable-static \
        --with-zlib=no --with-bzip2=no --with-png=no --with-harfbuzz=no --with-brotli=no \
        CC="$CC" CFLAGS="$COMMON_CFLAGS" LDFLAGS="$COMMON_LDFLAGS" CPPFLAGS="$COMMON_CPPFLAGS" \
        > /tmp/freetype_build.log 2>&1 || { tail -40 /tmp/freetype_build.log; exit 1; }
    make -j"$JOBS" >> /tmp/freetype_build.log 2>&1
    make install >> /tmp/freetype_build.log 2>&1
    echo "  FreeType installed"
fi

# -------------------------------------------------------------
# 2. SDL2_ttf 2.0.15
# -------------------------------------------------------------
if [ ! -f "$PREFIX/lib/libSDL2_ttf.a" ]; then
    echo "[2/6] Building SDL2_ttf 2.0.15..."
    cd "$BUILD"
    rm -rf SDL2_ttf-2.0.15
    $TAR -xzf "$SRC/SDL2_ttf-2.0.15.tar.gz"
    cd SDL2_ttf-2.0.15
    ./configure --host=powerpc-apple-darwin8 \
        --prefix="$PREFIX" \
        --disable-shared --enable-static \
        --with-sdl-prefix="$SDL_PREFIX" \
        --without-x \
        FT2_CFLAGS="-I$PREFIX/include/freetype2" \
        FT2_LIBS="-L$PREFIX/lib -lfreetype" \
        CC="$CC" CFLAGS="$COMMON_CFLAGS -include math.h -DSDL_ceilf=ceilf -I$SDL_PREFIX/include/SDL2 -I$PREFIX/include/freetype2" \
        LDFLAGS="$COMMON_LDFLAGS -L$SDL_PREFIX/lib -L$PREFIX/lib" \
        > /tmp/sdl2_ttf_build.log 2>&1 || { tail -40 /tmp/sdl2_ttf_build.log; exit 1; }
    make -j"$JOBS" >> /tmp/sdl2_ttf_build.log 2>&1
    make install >> /tmp/sdl2_ttf_build.log 2>&1
    echo "  SDL2_ttf installed"
fi

# -------------------------------------------------------------
# 3. Boost 1.76.0 (Headers + Boost.Filesystem + Boost.System)
# -------------------------------------------------------------
if [ ! -f "$PREFIX/lib/libboost_filesystem.a" ]; then
    echo "[3/6] Building Boost 1.76.0 (Filesystem + System)..."
    cd "$BUILD"
    if [ ! -d boost_1_76_0 ]; then
        $TAR -xjf "$SRC/boost_1_76_0.tar.bz2"
    fi
    cd boost_1_76_0
    
    echo "  Copying Boost headers..."
    cp -R boost "$PREFIX/include/"

    # alephone#11, 2026-08-28: boost::property_tree::iptree's default
    # comparator (less_nocase) does a locale-facet virtual call that this
    # PPC cross-toolchain miscompiles -- EXC_BAD_INSTRUCTION on real 10.5
    # hardware, indirect call landing in RTTI data instead of code. Every
    # MML/XML config file load goes through it (InfoTree : iptree), so this
    # isn't optional. See scripts/patches/ for the rationale in full.
    patch -p1 -d "$PREFIX/include" < /tmp/boost-1.76.0-less_nocase-no-locale.patch

    echo "  Compiling Boost.System..."
    $CXX $COMMON_CXXFLAGS -I. -c libs/system/src/error_code.cpp -o error_code.o
    $AR rc "$PREFIX/lib/libboost_system.a" error_code.o
    $RANLIB "$PREFIX/lib/libboost_system.a"
    
    echo "  Compiling Boost.Filesystem..."
    $CXX $COMMON_CXXFLAGS -I. -DBOOST_ALL_NO_LIB=1 -c \
        libs/filesystem/src/codecvt_error_category.cpp \
        libs/filesystem/src/directory.cpp \
        libs/filesystem/src/exception.cpp \
        libs/filesystem/src/operations.cpp \
        libs/filesystem/src/path.cpp \
        libs/filesystem/src/path_traits.cpp \
        libs/filesystem/src/portability.cpp \
        libs/filesystem/src/unique_path.cpp \
        libs/filesystem/src/utf8_codecvt_facet.cpp
    $AR rc "$PREFIX/lib/libboost_filesystem.a" \
        codecvt_error_category.o directory.o exception.o operations.o path.o \
        path_traits.o portability.o unique_path.o utf8_codecvt_facet.o
    $RANLIB "$PREFIX/lib/libboost_filesystem.a"
    echo "  Boost installed"
fi

# -------------------------------------------------------------
# 4. Asio 1.28.0 (Header-only)
# -------------------------------------------------------------
if [ ! -f "$PREFIX/include/asio.hpp" ]; then
    echo "[4/6] Installing Asio 1.28.0 headers..."
    cd "$BUILD"
    rm -rf asio-1.28.0
    $TAR -xjf "$SRC/asio-1.28.0.tar.bz2"
    cp -R asio-1.28.0/include/* "$PREFIX/include/"
    echo "  Asio installed"
fi

# -------------------------------------------------------------
# 5. libsndfile 1.2.2
# -------------------------------------------------------------
if [ ! -f "$PREFIX/lib/libsndfile.a" ]; then
    echo "[5/6] Building libsndfile 1.2.2..."
    cd "$BUILD"
    rm -rf libsndfile-1.2.2
    $TAR -xJf "$SRC/libsndfile-1.2.2.tar.xz"
    cd libsndfile-1.2.2
    
    # Patch missing strnlen on 10.3.9 SDK
    perl -pi -e 's/#include "common.h"/#include "common.h"\nstatic inline size_t strnlen(const char *s, size_t maxlen) { const char *p = (const char*)memchr(s, 0, maxlen); return p ? (size_t)(p - s) : maxlen; }/ if /#include "common.h"/' src/common.c

    ./configure --host=powerpc-apple-darwin8 \
        --prefix="$PREFIX" \
        --disable-shared --enable-static \
        --disable-external-libs --disable-sqlite --disable-alsa \
        CC="$CC" CXX="$CXX" CFLAGS="$COMMON_CFLAGS" CXXFLAGS="$COMMON_CXXFLAGS" \
        LDFLAGS="$COMMON_LDFLAGS" CPPFLAGS="$COMMON_CPPFLAGS" \
        > /tmp/sndfile_build.log 2>&1 || { tail -40 /tmp/sndfile_build.log; exit 1; }
    make -j"$JOBS" >> /tmp/sndfile_build.log 2>&1
    make install >> /tmp/sndfile_build.log 2>&1
    echo "  libsndfile installed"
fi

# -------------------------------------------------------------
# 6. openal-soft 1.23.1
# -------------------------------------------------------------
if [ ! -f "$PREFIX/lib/libopenal.a" ]; then
    echo "[6/6] Building openal-soft 1.23.1..."
    cd "$BUILD"
    if [ ! -d openal-soft-1.23.1 ]; then
        $TAR -xzf "$SRC/openal-soft-1.23.1.tar.gz"
    fi
    cd openal-soft-1.23.1
    
    # Generate config.h for 10.3.9 Darwin PPC
    cat > config.h << 'EOFCFG'
#pragma once
#define __STDC_FORMAT_MACROS 1
#include <inttypes.h>
#include <math.h>
#define HAVE_GETOPT 1
#define HAVE_DLFCN_H 1
#define HAVE_PTHREAD_SETSCHEDPARAM 1
#define RESTRICT __restrict
#ifdef __cplusplus
namespace std {
    using ::copysign;
    using ::log2;
    using ::cbrt;
    using ::exp2;
    using ::round;
    using ::trunc;
    using ::hypot;
}
#endif
EOFCFG

    cat > version.h << 'EOFV'
#pragma once
#define ALSOFT_VERSION "1.23.1"
#define ALSOFT_VERSION_NUM 1,23,1,0
#define ALSOFT_GIT_BRANCH "UNKNOWN"
#define ALSOFT_GIT_COMMIT_HASH "unknown"
EOFV

    # Replace common/threads.h with C++11 mutex/cv semaphore
    cat > common/threads.h << 'EOFTH'
#ifndef AL_THREADS_H
#define AL_THREADS_H

#include <mutex>
#include <condition_variable>

#define FORCE_ALIGN

void althrd_setname(const char *name);

namespace al {

class semaphore {
    std::mutex mtx;
    std::condition_variable cv;
    unsigned int count;

public:
    semaphore(unsigned int initial=0) : count(initial) {}
    semaphore(const semaphore&) = delete;
    ~semaphore() = default;

    semaphore& operator=(const semaphore&) = delete;

    void post() {
        std::lock_guard<std::mutex> lock(mtx);
        ++count;
        cv.notify_one();
    }
    void wait() noexcept {
        std::unique_lock<std::mutex> lock(mtx);
        cv.wait(lock, [this]{ return count > 0; });
        --count;
    }
    bool try_wait() noexcept {
        std::lock_guard<std::mutex> lock(mtx);
        if(count > 0) {
            --count;
            return true;
        }
        return false;
    }
};

} // namespace al

#endif /* AL_THREADS_H */
EOFTH

    cat > common/threads.cpp << 'EOFTP'
#include "config.h"
#include "threads.h"

void althrd_setname(const char *name) {
    (void)name;
}
EOFTP

    # Patch alc/alc.cpp for std::log2 fallback
    perl -pi -e 's/std::log2/log2/g' alc/alc.cpp

    mkdir -p "$PREFIX/include/AL"
    cp include/AL/*.h "$PREFIX/include/AL/"
    
    OPENAL_CXXFLAGS="$COMMON_CXXFLAGS -I. -Iinclude -Icommon -DAL_BUILD_LIBRARY -DAL_ALEXT_PROTOTYPES -D__STDC_FORMAT_MACROS=1 -DRESTRICT=__restrict"
    
    SOURCES="
    al/auxeffectslot.cpp al/buffer.cpp al/effect.cpp
    al/effects/autowah.cpp al/effects/chorus.cpp al/effects/compressor.cpp
    al/effects/convolution.cpp al/effects/dedicated.cpp al/effects/distortion.cpp
    al/effects/echo.cpp al/effects/effects.cpp al/effects/equalizer.cpp
    al/effects/fshifter.cpp al/effects/modulator.cpp al/effects/null.cpp
    al/effects/pshifter.cpp al/effects/reverb.cpp al/effects/vmorpher.cpp
    al/error.cpp al/event.cpp al/extension.cpp al/filter.cpp al/listener.cpp
    al/source.cpp al/state.cpp
    alc/alc.cpp alc/alconfig.cpp alc/alu.cpp
    alc/backends/base.cpp alc/backends/loopback.cpp alc/backends/null.cpp
    alc/context.cpp alc/device.cpp
    alc/effects/autowah.cpp alc/effects/chorus.cpp alc/effects/compressor.cpp
    alc/effects/convolution.cpp alc/effects/dedicated.cpp alc/effects/distortion.cpp
    alc/effects/echo.cpp alc/effects/equalizer.cpp alc/effects/fshifter.cpp
    alc/effects/modulator.cpp alc/effects/null.cpp alc/effects/pshifter.cpp
    alc/effects/reverb.cpp alc/effects/vmorpher.cpp alc/panning.cpp
    common/alcomplex.cpp common/alfstream.cpp common/almalloc.cpp
    common/alstring.cpp common/dynload.cpp common/polyphase_resampler.cpp
    common/ringbuffer.cpp common/strutils.cpp common/threads.cpp
    core/ambdec.cpp core/ambidefs.cpp core/bformatdec.cpp core/bs2b.cpp
    core/bsinc_tables.cpp core/buffer_storage.cpp core/context.cpp
    core/converter.cpp core/cpu_caps.cpp core/cubic_tables.cpp
    core/devformat.cpp core/device.cpp core/effectslot.cpp core/except.cpp
    core/filters/biquad.cpp core/filters/nfc.cpp core/filters/splitter.cpp
    core/fmt_traits.cpp core/fpu_ctrl.cpp core/helpers.cpp core/hrtf.cpp
    core/logging.cpp core/mastering.cpp core/mixer.cpp core/mixer/mixer_c.cpp
    core/uhjfilter.cpp core/uiddefs.cpp core/voice.cpp
    "
    
    objs=""
    for s in $SOURCES; do
        obj="${s%.cpp}.o"
        mkdir -p "$(dirname "$obj")"
        if [ ! -f "$obj" ]; then
            $CXX $OPENAL_CXXFLAGS -c "$s" -o "$obj"
        fi
        objs="$objs $obj"
    done
    
    $AR rc "$PREFIX/lib/libopenal.a" $objs
    $RANLIB "$PREFIX/lib/libopenal.a"
    
    # pkgconfig file for openal
    cat > "$PREFIX/lib/pkgconfig/openal.pc" << 'EOFPC'
prefix=/Users/mini/alephone-ppc-deps
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: OpenAL
Description: OpenAL Soft
Version: 1.23.1
Libs: -L${libdir} -lopenal
Cflags: -I${includedir} -I${includedir}/AL
EOFPC
    echo "  openal-soft installed"
fi

echo "[deps-ppc] all PPC dependencies built and verified successfully in $PREFIX"
ls -la "$PREFIX/lib"
REMOTE_SCRIPT

echo "[deps-ppc] done."
