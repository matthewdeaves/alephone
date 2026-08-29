#!/usr/bin/env bash
# deploy-dmg.sh - Put a built DMG onto a fleet machine the way a released
# artifact would land, without ever setting com.apple.quarantine ourselves
# (scp/rsync never do; that attribute only gets added by a quarantine-aware
# transfer like Safari/Mail/AirDrop, which internal fleet delivery is not).
# usage: scripts/deploy-dmg.sh <host-alias> [dmg-path]
# effect: mounts the DMG on <host-alias>, copies each game's folder (.app
#         plus its sibling data files) to ~/Desktop, strips quarantine
#         defensively, unmounts.

set -euo pipefail

HOST="${1:?usage: $0 <host-alias> [dmg-path]}"
DMG_PATH="${2:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "$DMG_PATH" ]; then
	DMG_PATH="$(ls -t "$REPO_ROOT"/dist/Marathon-OldMac-*.dmg 2>/dev/null | head -1)"
	[ -n "$DMG_PATH" ] || { echo "deploy-dmg.sh: no DMG in dist/ and none given" >&2; exit 1; }
fi
[ -f "$DMG_PATH" ] || { echo "deploy-dmg.sh: $DMG_PATH not found" >&2; exit 1; }

DMG_BASENAME="$(basename "$DMG_PATH")"
REMOTE_DMG="/tmp/$DMG_BASENAME"
REMOTE_MOUNT="/tmp/alephone-deploy-mount.$$"
REMOTE_QCLEAR="/tmp/clear-launch-quarantine.sh"
QCLEAR_SRC="$REPO_ROOT/scripts/clear-launch-quarantine.sh"

echo "[deploy] copying $DMG_BASENAME to $HOST:$REMOTE_DMG..."
scp -q "$DMG_PATH" "$HOST:$REMOTE_DMG"
# clear-launch-quarantine.sh (old-mac-build-host, synced into scripts/) is
# deliberately a local-step script, not something to pipe over ssh -- ship it
# to the target host and invoke it there rather than inlining its logic.
[ -f "$QCLEAR_SRC" ] && scp -q "$QCLEAR_SRC" "$HOST:$REMOTE_QCLEAR"

echo "[deploy] mounting and installing on $HOST..."
ssh "$HOST" bash -s -- "$REMOTE_DMG" "$REMOTE_MOUNT" "$REMOTE_QCLEAR" << 'REMOTE_DEPLOY'
# Not `set -o pipefail`: some fleet targets (e.g. Tiger 10.4's stock
# /bin/bash 2.05b) predate it entirely and abort with "invalid option name"
# on a bare `set -euo pipefail`, silently disabling -e/-u too since bash's
# `set` applies no flags at all when one is invalid.
set -eu
DMG="$1"
MOUNT="$2"
QCLEAR="$3"
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -quiet
shopt -s nullglob 2>/dev/null || true
FOUND=0

# Track exactly which .app paths this run deployed, newline-delimited (not a
# shell array: some fleet targets run an ancient /bin/bash) -- this Desktop
# is shared with other ports' fleet deployments, so the quarantine-clear step
# below must stay scoped to what we just installed, not every .app it finds.
DEPLOYED_LIST="/tmp/alephone-deployed-apps.$$"
: > "$DEPLOYED_LIST"

# Copy the .app's *containing folder*, not just the bundle: this layout
# ships each game's data (Map.scen, Shapes.shps, Sounds.sndz, Physics.phys,
# Music/, Plugins/, Scripts/) as siblings of the .app, not inside it -- same
# as what a real drag-to-Desktop of a mounted DMG folder would carry over.
for app in "$MOUNT"/*/*.app; do
	[ -d "$app" ] || continue
	FOUND=1
	src="$(dirname "$app")"
	name="$(basename "$src")"
	dest="$HOME/Desktop/$name"
	rm -rf "$dest"
	# ditto (not cp -R) to preserve resource forks / bundle metadata correctly.
	# NOTE: both cp -R and ditto PRESERVE com.apple.quarantine if the source
	# carries it -- this deploy path (scp) never sets it, but the DMG's
	# staged content could, so clear it explicitly rather than assume.
	ditto "$src" "$dest"
	echo "[deploy] installed $dest/"
	echo "$dest/$(basename "$app")" >> "$DEPLOYED_LIST"
done
# Fallback: an .app with no sibling data folder, sitting at the DMG root.
for app in "$MOUNT"/*.app; do
	[ -d "$app" ] || continue
	FOUND=1
	name="$(basename "$app")"
	dest="$HOME/Desktop/$name"
	rm -rf "$dest"
	ditto "$app" "$dest"
	echo "[deploy] installed $dest"
	echo "$dest" >> "$DEPLOYED_LIST"
done
[ "$FOUND" = 1 ] || { echo "deploy-dmg.sh: no .app bundles found in DMG" >&2; exit 1; }

# Quarantine-clear BEFORE detaching the DMG, not after: on some boxes (found
# on yosemite, Panther 10.3.9) hdiutil detach fails outright on the mounted
# path, and under set -eu that used to abort the whole script before this
# step ever ran -- apps sitting un-quarantine-cleared on a machine someone's
# about to double-click launch is a worse failure than a DMG staying mounted.
if [ -f "$QCLEAR" ]; then
	chmod +x "$QCLEAR"
	while IFS= read -r app; do
		"$QCLEAR" "$app"
	done < "$DEPLOYED_LIST"
else
	echo "deploy-dmg.sh: clear-launch-quarantine.sh not shipped, falling back to inline xattr" >&2
	while IFS= read -r app; do
		xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
	done < "$DEPLOYED_LIST"
fi
rm -f "$DEPLOYED_LIST"

# hdiutil detach by mountpoint PATH is unreliable on some boxes (measured on
# yosemite/Panther 10.3.9: "detach failed - No such file or directory" every
# time, regardless of path form) -- detach by device node works first try.
# Derive it from mount(8)'s own output and prefer that; fall back to the
# path form if the lookup comes up empty, and don't let either failure abort
# the deploy -- a DMG that won't detach is recoverable by hand later, unlike
# apps that never got quarantine-cleared.
#
# Match on the mountpoint's basename, not the full $MOUNT path: mount(8)
# reports the resolved path (/private/tmp/... on Panther/Tiger, where /tmp
# is a symlink), which never equals $MOUNT's unresolved /tmp/... form --
# measured 2026-08-29, an exact-path match here silently found nothing and
# fell through to the still-broken path-form detach. The mount point name
# is PID-suffixed (see MOUNT="$2" above) so basename alone stays unique.
mount_base="$(basename "$MOUNT")"
DEV="$(mount | awk -v b="$mount_base" '$0 ~ ("/" b " ") {print $1}')"
if [ -n "$DEV" ]; then
	hdiutil detach "$DEV" -quiet || echo "deploy-dmg.sh: detach by device ($DEV) failed, DMG left mounted at $MOUNT" >&2
else
	hdiutil detach "$MOUNT" -quiet || echo "deploy-dmg.sh: detach failed, DMG left mounted at $MOUNT" >&2
fi
rmdir "$MOUNT" 2>/dev/null || true
REMOTE_DEPLOY

ssh "$HOST" "rm -f '$REMOTE_DMG' '$REMOTE_QCLEAR'"
echo "[deploy] done: apps are on $HOST's Desktop"
