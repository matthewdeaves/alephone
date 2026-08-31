#!/usr/bin/env bash
# package-dmg.sh - Package Marathon 1, 2, Infinity into one Aleph One.app
# (built-in scenario chooser picks between them) and a DMG
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
mkdir -p "$STAGE_DIR/Aleph One/Scenarios"

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

	# Icon. Copy under its OWN filename, not "${GAME_NAME}.icns" -- those
	# coincided for Marathon1/2/3 (Marathon.icns, "Marathon 2.icns", ...)
	# but not for AlephOne/AlephOne.icns (no space) once GAME_NAME became
	# "Aleph One" (with one) for the single-bundle packaging (alephone#13):
	# the file landed in the bundle as "Aleph One.icns" while Info.plist's
	# CFBundleIconFile still said "AlephOne.icns" -- LaunchServices found
	# nothing and showed the default blank icon. Measured 2026-08-28 on
	# imac-2019, a real human looking at a real Finder icon, not a guess.
	if [ -f "$ICON_SRC" ]; then
		cp "$ICON_SRC" "$APP_DIR/Contents/Resources/$(basename "$ICON_SRC")"
	fi

	# Document icons
	cp "$REPO_ROOT/Xcode/App_Resources/DataFileIcons/"*.icns "$APP_DIR/Contents/Resources/" 2>/dev/null || true

	# Bundle the one dynamic dependency ppc doesn't statically link (SDL2 --
	# everything else statically links, see build.sh's fetch step) so the
	# app is self-contained instead of pointing at a bare build-host-
	# absolute path. Measured 2026-08-28 (alephone#5): without this, the fat
	# binary launches fine on machines that happen to share the build host's
	# exact directory layout and crashes with dyld "Library not loaded"
	# everywhere else -- including imac-2019, the P0 launch-reliability
	# target. Same shape as quakespasm bundling SDL.framework into
	# Contents/MacOS and retargeting to @executable_path.
	#
	# Prefer the fused universal dylib (x86_64+arm64, alephone#17) when
	# build.sh's fat step produced one; fall back to the plain x86_64-only
	# copy for a ppc+x86_64-only build (no arm64 slice built this run).
	SDL2_DYLIB="$REPO_ROOT/build/deps-fat/libSDL2-2.0.0.dylib"
	[ -f "$SDL2_DYLIB" ] || SDL2_DYLIB="$REPO_ROOT/build/deps-x86_64/libSDL2-2.0.0.dylib"
	if [ -f "$SDL2_DYLIB" ]; then
		mkdir -p "$APP_DIR/Contents/Frameworks"
		cp "$SDL2_DYLIB" "$APP_DIR/Contents/Frameworks/libSDL2-2.0.0.dylib"
		chmod +w "$APP_DIR/Contents/Frameworks/libSDL2-2.0.0.dylib"
		install_name_tool -id "@executable_path/../Frameworks/libSDL2-2.0.0.dylib" \
			"$APP_DIR/Contents/Frameworks/libSDL2-2.0.0.dylib"
		# The @executable_path retarget itself happens earlier, on each
		# THIN slice (x86_64 in build.sh, arm64 in build-arm64.sh), before
		# either lipo (into the fused universal dylib above) or bundling.
		# Apple's current install_name_tool cannot parse the PPC cross-
		# compiled app slice's load commands at all ("malformed load
		# command 0 (cmdsize is zero)", measured 2026-08-28) and aborts on
		# any fat file containing it, so this never touches the app binary
		# itself. It's safe here because this dylib is its own standalone
		# file with no PPC content -- an x86_64+arm64 fat SDL2 dylib is
		# fine, since install_name_tool parses both of those slices' load
		# commands without issue; ppc is what it can't handle.
	else
		echo "WARNING: $SDL2_DYLIB not found -- x86_64/arm64 slices will crash at" >&2
		echo "  launch off this build host. Run scripts/build.sh x86_64 and/or" >&2
		echo "  scripts/build-arm64.sh first." >&2
	fi

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

# alephone#13: one app, not three. The engine's own built-in ScenarioChooser
# (Source_Files/Misc/ScenarioChooser.{h,cpp}) already does exactly this --
# scans the app's own containing folder for a "primary" scenario
# (add_primary_scenario, shell.cpp) plus a Scenarios/ subfolder for
# everything else (add_directory: "assume each visible subdirectory is a
# scenario") and shows a pick screen if it finds more than one. Never wired
# up in this fork's packaging before now -- was building three separate app
# bundles instead, each with its own copy of the engine binary.
#
# Xcode/App_Resources/AlephOne/{AlephOne.icns,Info.plist} is upstream's own
# umbrella identity for exactly this shape (CFBundleName "Aleph One",
# distinct from any one game's), not something invented for this fork.
echo "[1/2] Creating Aleph One.app (Marathon 1 as primary scenario, 2/Infinity via the built-in chooser)..."
create_app_bundle "Aleph One" \
	"$STAGE_DIR/Aleph One/Aleph One.app" \
	"$REPO_ROOT/Xcode/App_Resources/AlephOne/AlephOne.icns" \
	"$REPO_ROOT/Xcode/App_Resources/AlephOne/Info.plist"
# Primary scenario: siblings of the .app itself (matches add_primary_scenario
# using kPathDefaultData, which resolves to the app's own containing folder).
rsync -a --exclude='.git' /tmp/data-marathon/ "$STAGE_DIR/Aleph One/"
# Everything else: one subdirectory per scenario under Scenarios/.
rsync -a --exclude='.git' /tmp/data-marathon-2/ "$STAGE_DIR/Aleph One/Scenarios/Marathon 2/"
rsync -a --exclude='.git' /tmp/data-marathon-infinity/ "$STAGE_DIR/Aleph One/Scenarios/Marathon Infinity/"

# Add README
cat > "$STAGE_DIR/README.txt" << 'EOF'
Aleph One — Marathon 1, 2, & Infinity for Mac OS X
Universal Fat Binary spanning PowerPC (10.3.9 Panther / 10.4 Tiger / 10.5 Leopard) and Intel (10.4 through 10.7+).

Running the games:
  - Double-click Aleph One.app. A scenario picker shows Marathon, Marathon 2,
    and Marathon Infinity -- pick one to play. Each remembers its own saved
    games and preferences separately.
EOF

# Defense in depth: strip quarantine from the whole staged tree (scenario
# data was rsync'd from /tmp, which may itself have picked up the attribute).
if [ -x "$REPO_ROOT/scripts/clear-launch-quarantine.sh" ]; then
	"$REPO_ROOT/scripts/clear-launch-quarantine.sh" "$STAGE_DIR"
else
	xattr -dr com.apple.quarantine "$STAGE_DIR" 2>/dev/null || true
fi

echo "[2/2] Creating DMG disk image..."
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
