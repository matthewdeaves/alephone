#!/usr/bin/env bash
# package-dmg.sh - Package Marathon 1, 2, Infinity into standalone .app bundles and DMG
# usage: scripts/package-dmg.sh
# output: dist/Marathon-OldMac.dmg

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# --match restricts to client-tag patterns (release-* / vX.Y.Z) so this never
# picks up a server-vX.Y.Z tag pointing at the same commit -- that collision
# is real: server-v1.0.0 (alephone#9) and this script's HEAD landed on the
# same commit, and a bare `git describe` named a CLIENT dmg
# "Marathon-OldMac-server-v1.0.0.dmg" (measured 2026-08-28).
VERSION="$(git describe --tags --always --dirty --match 'release-*' --match 'v[0-9]*' 2>/dev/null || echo "1.11")"
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

	# Info.plist parsing for executable name
	local EXEC_NAME="$GAME_NAME"
	if [ -f "$PLIST_SRC" ]; then
		# Extract CFBundleExecutable using sed
		EXEC_NAME=$(sed -n '/<key>CFBundleExecutable<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$PLIST_SRC")
	fi

	# Binary
	cp "$BIN_SRC" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
	chmod +x "$APP_DIR/Contents/MacOS/$EXEC_NAME"

	# PkgInfo
	echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

	# Info.plist
	if [ -f "$PLIST_SRC" ]; then
		cp "$PLIST_SRC" "$APP_DIR/Contents/Info.plist"
		# Patch LSMinimumSystemVersion in the copied plist for Panther/Tiger support
		sed -i '' -e '/<key>LSMinimumSystemVersion<\/key>/{n;s/<string>.*<\/string>/<string>10.3.9<\/string>/;}' "$APP_DIR/Contents/Info.plist"
		# Replace Xcode variable placeholders that break modern Gatekeeper/LaunchServices
		sed -i '' -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/org.bungie.alephone.${GAME_NAME// /}/g" \
				  -e "s/A1_DISPLAY_VERSION/${VERSION}/g" \
				  -e "s/A1_DATE_VERSION/${VERSION}/g" \
				  "$APP_DIR/Contents/Info.plist"
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

	# Strip any quarantine attribute that hitched a ride on a source asset
	# (icons, data files) before we sign — codesign rejects a quarantined tree.
	# Canonical primitive (old-mac-build-host#34); falls back to inline xattr
	# if this tree predates the sync.
	if [ -x "$REPO_ROOT/scripts/clear-launch-quarantine.sh" ]; then
		"$REPO_ROOT/scripts/clear-launch-quarantine.sh" "$APP_DIR"
	else
		xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
	fi

	# Ad-hoc sign so Gatekeeper's assessment on Catalina+ can succeed at all.
	# Without any signature, a quarantined+unsigned app on modern macOS commonly
	# shows "app is damaged and can't be opened, move to trash" (mistaken for
	# corruption) instead of the milder "unidentified developer" prompt. Ad-hoc
	# (-s -) needs no certificate; it does not survive Gatekeeper's online
	# notarization check, but it fixes the false-corruption failure mode.
	# lipo'd ppc/x86_64 fat binaries: codesign signs each slice independently,
	# so this must run after the binary is final, not before lipo.
	if codesign --force --deep -s - "$APP_DIR" 2>/tmp/codesign-${GAME_NAME// /_}.log; then
		codesign --verify --verbose=2 "$APP_DIR" 2>&1 | sed 's/^/  [codesign] /'
	else
		echo "WARNING: ad-hoc codesign failed for $APP_DIR, see /tmp/codesign-${GAME_NAME// /_}.log" >&2
		cat "/tmp/codesign-${GAME_NAME// /_}.log" >&2
	fi
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

# Defense in depth: strip quarantine from the whole staged tree (scenario
# data was rsync'd from /tmp, which may itself have picked up the attribute).
if [ -x "$REPO_ROOT/scripts/clear-launch-quarantine.sh" ]; then
	"$REPO_ROOT/scripts/clear-launch-quarantine.sh" "$STAGE_DIR"
else
	xattr -dr com.apple.quarantine "$STAGE_DIR" 2>/dev/null || true
fi

echo "[4/4] Creating DMG disk image..."
DMG_PATH="$DIST_DIR/$DMG_NAME"
rm -f "$DMG_PATH"
# -layout SPUD: classic Apple Partition Map, not hdiutil's modern default
# (GPT, with a protective MBR + GUID partition table). GPT postdates every
# PowerPC Mac -- it was introduced for the first Intel Macs (2006) -- so a
# GPT-schemed DMG built with hdiutil's bare default on any host running a
# reasonably modern macOS (verified on 26.x here) fails to mount at all on
# real 10.3.9 Panther hardware ("no mountable file systems"), the project's
# primary target. Tiger 10.4+ can read GPT (it had to, for early Intel Macs),
# which is why this went unnoticed until testing landed on a real G3.
hdiutil create -volname "Marathon Games" \
	-srcfolder "$STAGE_DIR" \
	-ov -format UDZO \
	-fs HFS+ \
	-layout SPUD \
	"$DMG_PATH"

echo "================================================================"
echo "DMG successfully created:"
echo "  $DMG_PATH"
echo "  Size: $(ls -lh "$DMG_PATH" | awk '{print $5}')"
echo "================================================================"
