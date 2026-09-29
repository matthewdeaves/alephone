# Build and fleet operations

## Build
`scripts/build.sh` selects a free build host. PPC dependencies exist only on mini-intel, so use `BUILD_HOSTS=mini-intel`; `BUILD_HOST=` bypasses the lock. Dependency drivers are `scripts/build-deps-*.sh`. Host setup: `BUILD-HOST.md`; PPC dependencies and SDL2 floor: `.claude/rules/ppc-facts.md`; crash lessons: `docs/ppc-lessons.md`; plan: `PORTING-PPC.md`.

## Package and deploy
`scripts/package-dmg.sh` creates the DMG. Deploy and smoke use the pinned tools through `scripts/shared.sh deploy-dmg.sh` and `scripts/shared.sh smoke-dmg.sh`. Shared-tool overrides (`BENCH_ADAPTER`, `DMG_PORT_CONF`, full DMG path) are in `docs/SHARED-TOOLS.md`.

## Bench
The port adapter is `scripts/bench-adapter.sh`. Reach evidence tools through `scripts/shared.sh`; `BENCH_ADAPTER=scripts/bench-adapter.sh` selects the adapter. VM staging and the one-claim command sequence are in `docs/VM-TIGER.md`.

## Claim failure story

Never pipe `pick-bench-host.sh --acquire`; `| tail` hid a failed acquisition on 2026-09-23. The incident is in `INCIDENTS.md`.
