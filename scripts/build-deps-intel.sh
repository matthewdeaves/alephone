#!/usr/bin/env bash
# build-deps-intel.sh - Build 6 Aleph One dependencies for x86_64 Intel Mac on mini-intel
# Target: x86_64 Intel (Mac OS X 10.6+)
# Toolchain: GCC 7.5.0 (/Users/mini/gcc14-ppc-build/tools/gcc-7.5.0-host/bin)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILD_HOST="mini-intel"
echo "[deps-intel] building x86_64 Intel dependencies on $BUILD_HOST..."

ssh "$BUILD_HOST" 'bash -s' << 'REMOTE_SCRIPT'
set -euo pipefail

PREFIX="/Users/mini/alephone-intel-deps"
SRC_DIR="/Users/mini/alephone-deps-src"
BUILD_DIR="/Users/mini/alephone-deps-build-intel"
TOOLCHAIN="/Users/mini/gcc14-ppc-build/tools/gcc-7.5.0-host"
SDL_DIR="/Users/mini/oldmac/sdl2-x86_64"

mkdir -p "$PREFIX/include" "$PREFIX/lib" "$PREFIX/lib/pkgconfig" "$BUILD_DIR"

export PATH="$TOOLCHAIN/bin:/Users/mini/local/bin:$PATH"
export CC="$TOOLCHAIN/bin/gcc-7"
export CXX="$TOOLCHAIN/bin/g++-7"
export AR="/usr/bin/ar"
export RANLIB="/usr/bin/ranlib"
export CFLAGS="-O2 -mmacosx-version-min=10.6 -fPIC"
export CXXFLAGS="-O2 -std=c++17 -mmacosx-version-min=10.6 -fPIC"
export LDFLAGS="-mmacosx-version-min=10.6 -L$PREFIX/lib -L$SDL_DIR/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$SDL_DIR/lib/pkgconfig"

echo "=== [1/6] FreeType 2.12.1 ==="
if [ ! -f "$PREFIX/lib/libfreetype.a" ]; then
    cd "$BUILD_DIR"
    rm -rf freetype-2.12.1
    tar -xf "$SRC_DIR/freetype-2.12.1.tar.gz"
    cd freetype-2.12.1
    ./configure --prefix="$PREFIX" \
        --enable-static --disable-shared \
        --without-zlib --without-bzip2 --without-png --without-harfbuzz \
        CC="$CC" CFLAGS="$CFLAGS"
    make -j2
    make install
fi

echo "=== [2/6] SDL2_ttf 2.0.15 ==="
if [ ! -f "$PREFIX/lib/libSDL2_ttf.a" ]; then
    cd "$BUILD_DIR"
    rm -rf SDL2_ttf-2.0.15
    tar -xf "$SRC_DIR/SDL2_ttf-2.0.15.tar.gz"
    cd SDL2_ttf-2.0.15
    ./configure --prefix="$PREFIX" \
        --enable-static --disable-shared \
        --with-ft-prefix="$PREFIX" \
        --with-sdl-prefix="$SDL_DIR" \
        CC="$CC" CFLAGS="$CFLAGS -I$PREFIX/include/freetype2" \
        FT2_CFLAGS="-I$PREFIX/include/freetype2" \
        FT2_LIBS="-L$PREFIX/lib -lfreetype" \
        SDL_CFLAGS="-I$SDL_DIR/include -I$SDL_DIR/include/SDL2" \
        SDL_LIBS="-L$SDL_DIR/lib -lSDL2"
    make -j2
    make install
fi

echo "=== [3/6] Boost 1.76.0 (Filesystem + System) ==="
if [ ! -f "$PREFIX/lib/libboost_filesystem.a" ]; then
    cd "$BUILD_DIR/boost_1_76_0"
    if [ ! -f b2 ]; then
        cd tools/build/src/engine
        ./build.sh --cxx="$CXX" gcc
        cp b2 "$BUILD_DIR/boost_1_76_0/"
        cd "$BUILD_DIR/boost_1_76_0"
    fi
    cat > user-config.jam << EOF
using gcc : 7.5 : $CXX : <cflags>"$CFLAGS" <cxxflags>"$CXXFLAGS" ;
EOF
    ./b2 -j2 --user-config=user-config.jam toolset=gcc-7.5 \
        --with-filesystem --with-system \
        link=static runtime-link=static variant=release \
        stage
    cp stage/lib/libboost_*.a "$PREFIX/lib/"
    cp -R boost "$PREFIX/include/"
fi

echo "=== [4/6] Asio 1.28.0 ==="
if [ ! -f "$PREFIX/include/asio.hpp" ]; then
    cp -R /Users/mini/alephone-ppc-deps/include/asio* "$PREFIX/include/" 2>/dev/null || {
        cd "$BUILD_DIR"
        tar -xf "$SRC_DIR/asio-1.28.0.tar.bz2" || true
        cp -R asio-1.28.0/include/* "$PREFIX/include/"
    }
fi

echo "=== [5/6] libsndfile 1.2.2 ==="
if [ ! -f "$PREFIX/lib/libsndfile.a" ]; then
    cd "$BUILD_DIR"
    rm -rf libsndfile-1.2.2
    tar -xf "$SRC_DIR/libsndfile-1.2.2.tar.xz"
    cd libsndfile-1.2.2
    ./configure --prefix="$PREFIX" \
        --enable-static --disable-shared \
        --disable-external-libs --disable-alsa --disable-sqlite \
        CC="$CC" CXX="$CXX" CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS"
    make -j2
    make install
fi

echo "=== [6/6] openal-soft 1.23.1 ==="
if [ ! -f "$PREFIX/lib/libopenal.a" ]; then
    cd "$BUILD_DIR"
    rm -rf openal-soft-1.23.1
    tar -xf "$SRC_DIR/openal-soft-1.23.1.tar.gz"
    cd openal-soft-1.23.1
    mkdir -p build && cd build
    cmake .. \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_C_COMPILER="$CC" \
        -DCMAKE_CXX_COMPILER="$CXX" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DLIBTYPE=STATIC \
        -DALSOFT_UTILS=OFF \
        -DALSOFT_EXAMPLES=OFF \
        -DALSOFT_TESTS=OFF \
        -DALSOFT_BACKEND_PIPEWIRE=OFF \
        -DALSOFT_BACKEND_PULSEAUDIO=OFF \
        -DALSOFT_BACKEND_ALSA=OFF \
        -DALSOFT_BACKEND_OSS=OFF \
        -DALSOFT_BACKEND_PORTAUDIO=OFF \
        -DALSOFT_BACKEND_SNDIO=OFF \
        -DALSOFT_BACKEND_COREAUDIO=ON \
        -DALSOFT_EMBED_HRTF_DATA=OFF
    make -j2
    make install
fi

echo "[deps-intel] ALL 6 INTEL DEPENDENCIES BUILT AND VERIFIED IN $PREFIX"
ls -la "$PREFIX/lib"
REMOTE_SCRIPT
