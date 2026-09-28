# Aleph One old-Mac port

Marathon 1/2/Infinity on the current Aleph One engine, one fat binary: ppc (10.3.9 target, 10.4 fallback), i386, x86_64, arm64. Scenarios are submodules in `data/Scenarios/`. Fork of `Aleph-One-Marathon/alephone`.

## Rules (each one a mistake that happened)
- Never PR, push a branch or file an issue upstream; the maintainer refuses porting patches.
- Never pipe `pick-bench-host.sh --acquire`: `| tail` hid a failed claim (INCIDENTS 2026-09-23).
- `build.sh` grabs any free host, but ppc deps exist only on mini-intel: `BUILD_HOSTS=mini-intel` (never `BUILD_HOST=`, which skips the lock).
- A PPC binary passes `nm -arch ppc -u` against the 10.3.9 SDK, or dyld aborts at launch on a G3.
- Treat any `std::locale`-facet call as a PPC crash suspect (`docs/ppc-lessons.md`).
- Client tags are `vX.Y.Z`; `server-vX.Y.Z` is separate. Delete old releases without `--cleanup-tag`.
- qemu-tiger3d, one claim: `scripts/shared.sh pick-bench-host.sh --run qemu-tiger3d "<label>" -- <script>` running `deploy-dmg.sh`, `smoke-dmg.sh`, `bench-evidence.sh` (`BENCH_ARTEFACT=<staged binary> BENCH_ADAPTER=scripts/bench-adapter.sh`), `qemu-vm.sh screendump <png>`. See `old-mac-build-host/docs/qemu-vm.md`.

## Where to look
- Build and deps: `scripts/build.sh`, `scripts/build-deps-*.sh`; host setup `BUILD-HOST.md`.
- Package, deploy, smoke, bench: `scripts/package-dmg.sh`, `scripts/bench-adapter.sh`; the rest via `scripts/shared.sh`.
- PPC toolchain and crash lessons: `docs/ppc-lessons.md`; deps and SDL2 floor: `.claude/rules/ppc-facts.md`.
- Port plan and target matrix: `PORTING-PPC.md` (`grep -n '^## '`).
- Dedicated server: `SERVER.md`. Tiger VM renderer: `docs/VM-TIGER.md`.
- Tests: `tests/` (Catch2 `replay_film_test.cpp` checks endian and replay). CI: `.claude/rules/builds-and-ci.md`.
- Fix and incident history: `grep -n '#NN' BUGFIXES.md INCIDENTS.md`; older in `docs/archive/`.
- Upstream engine docs: `docs/` (Lua, MML, netgame).
