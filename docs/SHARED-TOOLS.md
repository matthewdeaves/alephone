# Shared fleet tools

The pinned shared-script route and per-script overrides.
Host provisioning and compiler bootstrap remain in `BUILD-HOST.md`.
Section: Shared fleet scripts.

## Shared fleet scripts (build-host#105 pin, alephone#43)

This repo no longer carries copies of `pick-build-host.sh`, `pick-bench-host.sh`,
`deploy-dmg.sh`, `smoke-dmg.sh`, `bench-evidence.sh`, `bench-compare.sh`,
`gui-precondition.sh` or `clear-launch-quarantine.sh`. `shared-scripts.pin` (repo
root) names the `old-mac-build-host` revision they're fetched from; run any of
them as `scripts/shared.sh <name>.sh [args...]` (needs a sibling
`../old-mac-build-host` checkout, or `OLDMAC_BUILDHOST_REPO` set). `source-stamp.sh`
stays a real copy — it's sourced, not exec'd, so it can't go through the wrapper.

Two scripts need an explicit override every time, because they locate
port-specific files relative to their OWN path, which is the pin's read-only
cache once fetched, not this repo:

- **`bench-evidence.sh`** needs `BENCH_ADAPTER="$REPO_ROOT/scripts/bench-adapter.sh"`
  — without it, it looks for `bench-adapter.sh` next to itself in the cache and
  won't find our port-owned adapter.
- **`deploy-dmg.sh`** / **`smoke-dmg.sh`** need `DMG_PORT_CONF="$REPO_ROOT/scripts/dmg-port.conf"`
  — same reason, for `dmg-port.conf`. `deploy-dmg.sh` additionally derives its
  `dist/*.dmg` lookup from its own path when given a bare version string (e.g.
  `v1.2.0`) — that resolves to the wrong directory once pinned, so always pass
  a full path instead: `scripts/shared.sh deploy-dmg.sh <host> "$REPO_ROOT/dist/Marathon-OldMac-v1.2.0.dmg"`.
  Flagged to buildhost as a gap in the pin model itself (no analogous override
  for `deploy-dmg.sh`'s `REPO_ROOT`); this is the workaround until that lands.
