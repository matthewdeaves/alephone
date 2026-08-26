#!/usr/bin/env bash
# package-dmg.sh - Package Marathon 1, 2, Infinity into standalone .app bundles and DMG
# usage: scripts/package-dmg.sh
# output: dist/Marathon-OldMac.dmg

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo "1.11")"
DIST_DIR="$REPO_ROOT/dist"
STAGE_DIR="$REPO_ROOT/dist/staging-dmg"
DMG_NAME="Marathon-OldMac-${VERSION}.dmg"

mkdir -p "$DIST_DIR" "$STAGE_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/Marathon" "$STAGE_DIR/Marathon 2" "$STAGE_DIR/Marathon Infinity"

# Ensure binary exists (use fat binary if available, else PPC binary)
BIN_SRC="$REPO_ROOT/build/alephone"
if [ ! -f "$BIN_SRC" ]; then
	BIN_SRC="$REPO_ROOT/build/alephone-ppc"
fi
[ -f "$BIN_SRC" ] || { echo "package-dmg.sh: no binary found in build/"; exit 1; }

echo "================================================================"
echo "Packaging Marathon Games for Mac OS X (Panther/Tiger/Leopard/Lion)"
echo "  Engine Binary: $BIN_SRC"
echo "  Version:       $VERSION"
echo "================================================================"

create_app_bundle() {
	local GAME_NAME="$1"
	local APP_DIR="$2"
	local ICON_SRC="$3"
	local PLIST_SRC="$4"

	mkdir -p "$APP_DIR/Contents/MacOS"
	mkdir -p "$APP_DIR/Contents/Resources"

	# Binary
	cp "$BIN_SRC" "$APP_DIR/Contents/MacOS/$GAME_NAME"
	chmod +x "$APP_DIR/Contents/MacOS/$GAME_NAME"

	# PkgInfo
	echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

	# Info.plist
	if [ -f "$PLIST_SRC" ]; then
		cp "$PLIST_SRC" "$APP_DIR/Contents/Info.plist"
	else
		cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>${GAME_NAME}</string>
	<key>CFBundleIconFile</key>
	<string>${GAME_NAME}.icns</string>
	<key>CFBundleIdentifier</key>
	<string>org.bungie.alephone.${GAME_NAME// /}</string>
	<key>CFBundleName</key>
	<string>${GAME_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key>
	<string>10.3.9</string>
</dict>
</plist>
EOF
	fi

	# Icon
	if [ -f "$ICON_SRC" ]; then
		cp "$ICON_SRC" "$APP_DIR/Contents/Resources/${GAME_NAME}.icns"
	fi

	# Document icons
	cp "$REPO_ROOT/Xcode/App_Resources/DataFileIcons/"*.icns "$APP_DIR/Contents/Resources/" 2>/dev/null || true
}

echo "[1/4] Creating Marathon.app..."
create_app_bundle "Marathon" \
	"$STAGE_DIR/Marathon/Marathon.app" \
	"$REPO_ROOT/Xcode/App_Resources/Marathon1/Marathon.icns" \
	"$REPO_ROOT/Xcode/App_Resources/Marathon1/Info.plist"
rsync -a --exclude='.git' /tmp/data-marathon/ "$STAGE_DIR/Marathon/"

echo "[2/4] Creating Marathon 2.app..."
create_app_bundle "Marathon 2" \
	"$STAGE_DIR/Marathon 2/Marathon 2.app" \
	"$REPO_ROOT/Xcode/App_Resources/Marathon2/Marathon 2.icns" \
	"$REPO_ROOT/Xcode/App_Resources/Marathon2/Info.plist"
rsync -a --exclude='.git' /tmp/data-marathon-2/ "$STAGE_DIR/Marathon 2/"

echo "[3/4] Creating Marathon Infinity.app..."
create_app_bundle "Marathon Infinity" \
	"$STAGE_DIR/Marathon Infinity/Marathon Infinity.app" \
	"$REPO_ROOT/Xcode/App_Resources/Marathon3/Marathon Infinity.icns" \
	"$REPO_ROOT/Xcode/App_Resources/Marathon3/Info.plist"
rsync -a --exclude='.git' /tmp/data-marathon-infinity/ "$STAGE_DIR/Marathon Infinity/"

# Add README
cat > "$STAGE_DIR/README.txt" << 'EOF'
Aleph One — Marathon 1, 2, & Infinity for Mac OS X
Universal Fat Binary spanning PowerPC (10.3.9 Panther / 10.4 Tiger / 10.5 Leopard) and Intel (10.4 through 10.7+).

Running the games:
  - Double-click Marathon.app, Marathon 2.app, or Marathon Infinity.app inside their respective folders.
EOF

echo "[4/4] Creating DMG disk image..."
DMG_PATH="$DIST_DIR/$DMG_NAME"
rm -f "$DMG_PATH"
hdiutil create -volname "Marathon Games" \
	-srcfolder "$STAGE_DIR" \
	-ov -format UDZO \
	"$DMG_PATH"

echo "================================================================"
echo "DMG successfully created:"
echo "  $DMG_PATH"
echo "  Size: $(ls -lh "$DMG_PATH" | awk '{print $5}')"
echo "================================================================"
