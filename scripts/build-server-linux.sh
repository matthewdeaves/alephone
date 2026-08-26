#!/usr/bin/env bash
# Build the Linux dedicated-server release for Aleph One standalone hub.
#
# usage: scripts/build-server-linux.sh [--arch x86_64|aarch64] [--version V]
#        [--allow-dirty]
# output: dist/server/alephone-server-<version>-linux-<arch>.tar.gz

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ARCH="x86_64"
VERSION=""
VERSION_GIVEN=0
ALLOW_DIRTY=0

while [ $# -gt 0 ]; do
	case "$1" in
		--arch)    ARCH="${2:?--arch needs a value}"; shift 2 ;;
		--version) VERSION="${2:?--version needs a value}"; VERSION_GIVEN=1; shift 2 ;;
		--allow-dirty) ALLOW_DIRTY=1; shift ;;
		-h|--help) sed -n '2,6p' "$0"; exit 0 ;;
		*) echo "$0: unknown argument: $1" >&2; exit 2 ;;
	esac
done

case "$ARCH" in
	x86_64)  DOCKER_PLATFORM="linux/amd64" ;;
	aarch64) DOCKER_PLATFORM="linux/arm64" ;;
	*) echo "$0: unsupported arch: $ARCH (expected x86_64 or aarch64)" >&2; exit 2 ;;
esac

if [ -z "$VERSION" ]; then
	VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo "1.11")"
fi
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"

echo "================================================================"
echo "Aleph One Dedicated Server Linux Release Build"
echo "  Target:   Linux $ARCH ($DOCKER_PLATFORM)"
echo "  Version:  $VERSION"
echo "  Commit:   $GIT_COMMIT"
echo "================================================================"

IMAGE="oldmac-alephone-server-build:deb11-amd64"
STAGE_DIR="$REPO_ROOT/dist/staging/alephone-server-${VERSION}-linux-${ARCH}"
DIST_DIR="$REPO_ROOT/dist/server"
WORK_DIR="$REPO_ROOT/build/server-linux-${ARCH}"

rm -rf "$STAGE_DIR" "$WORK_DIR"
mkdir -p "$STAGE_DIR" "$DIST_DIR" "$WORK_DIR"

echo "[1/3] Ensuring build container is available..."
DOCKER_DEFAULT_PLATFORM=linux/amd64 docker build -t "$IMAGE" -f scripts/docker/server-build.Dockerfile scripts/docker >/dev/null

echo "[2/3] Compiling standalone_hub inside container..."
if [ "$ARCH" = "x86_64" ]; then
	docker run --rm \
		-v "$REPO_ROOT:/workspace:ro" \
		-v "$WORK_DIR:/build" \
		-w /build \
		"$IMAGE" bash -c "
			set -euo pipefail
			dpkg --add-architecture amd64
			apt-get update >/dev/null 2>&1
			apt-get install -y --no-install-recommends g++-x86-64-linux-gnu \
				libboost-filesystem-dev:amd64 libboost-system-dev:amd64 \
				libsdl2-dev:amd64 libsdl2-ttf-dev:amd64 libopenal-dev:amd64 \
				libsndfile1-dev:amd64 libpng-dev:amd64 zlib1g-dev:amd64 >/dev/null 2>&1
			mkdir -p /tmp/src
			cp -a /workspace/. /tmp/src/
			cd /tmp/src
			find Source_Files -name '*.o' -delete -o -name '*.a' -delete || true
			PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig ./configure --host=x86_64-linux-gnu \
				--enable-standalone-hub --disable-opengl \
				--without-vpx --without-matroska --without-ebml --without-libyuv --without-nfd \
				--without-curl --without-zzip --without-miniupnpc --without-sdl_image --disable-steam --without-catch2 \
				CC=x86_64-linux-gnu-gcc CXX=x86_64-linux-gnu-g++ \
				CXXFLAGS='-O2 -std=c++17' OBJCXXFLAGS='-O2 -std=c++17' LIBS='-lpthread'
			make -j\$(nproc)
			x86_64-linux-gnu-strip Source_Files/standalone_hub
			cp Source_Files/standalone_hub /build/alephone-server
		"
else
	docker run --rm \
		-v "$REPO_ROOT:/workspace:ro" \
		-v "$WORK_DIR:/build" \
		-w /build \
		"$IMAGE" bash -c "
			set -euo pipefail
			mkdir -p /tmp/src
			cp -a /workspace/. /tmp/src/
			cd /tmp/src
			find Source_Files -name '*.o' -delete -o -name '*.a' -delete || true
			./configure --enable-standalone-hub --disable-opengl \
				--without-vpx --without-matroska --without-ebml --without-libyuv --without-nfd \
				--without-curl --without-zzip --without-miniupnpc --without-sdl_image --disable-steam --without-catch2 \
				CXXFLAGS='-O2 -std=c++17' OBJCXXFLAGS='-O2 -std=c++17' LIBS='-lpthread'
			make -j\$(nproc)
			strip Source_Files/standalone_hub
			cp Source_Files/standalone_hub /build/alephone-server
		"
fi

cp "$WORK_DIR/alephone-server" "$STAGE_DIR/alephone-server"
chmod +x "$STAGE_DIR/alephone-server"

cat > "$STAGE_DIR/README.txt" << EOF
Aleph One Dedicated Server (standalone_hub)
Version: ${VERSION}
Architecture: Linux ${ARCH}

Usage:
  ./alephone-server -p <port> [options]

Options:
  -p, --port PORT          Port number to listen on (required)
  -n, --name NAME          Server / Room name announced on metaserver
  -m, --metaserver HOST    Metaserver hostname (default: metaserver.lhowon.org)
  -g, --game TYPE          Marathon game type (1 = Marathon, 2 = M2, 3 = Infinity)

Running with systemd:
  See retro-server-infra deployment scripts for service configurations.
EOF

cat > "$STAGE_DIR/BUILD-INFO.txt" << EOF
Aleph One Dedicated Server
Version: ${VERSION}
Arch: ${ARCH}
Git Commit: ${GIT_COMMIT}
Build Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Toolchain: Debian 11 (glibc 2.31) GCC 10 (C++17)
EOF

echo "[3/3] Packaging release tarball..."
TARBALL="$DIST_DIR/alephone-server-${VERSION}-linux-${ARCH}.tar.gz"
tar -czf "$TARBALL" -C "$REPO_ROOT/dist/staging" "alephone-server-${VERSION}-linux-${ARCH}"
rm -rf "$STAGE_DIR" "$WORK_DIR"

echo "================================================================"
echo "Successfully built Linux server release:"
echo "  $TARBALL"
echo "  Size: $(ls -lh "$TARBALL" | awk '{print $5}')"
echo "================================================================"
