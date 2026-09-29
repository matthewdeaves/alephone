# Aleph One old-Mac port

Marathon 1/2/Infinity on the current Aleph One engine, forked from `Aleph-One-Marathon/alephone`: one fat binary, ppc (10.3.9 target, 10.4 fallback), i386, x86_64, arm64 (matrix in `PORTING-PPC.md`); scenarios are submodules in `data/Scenarios/`.

## Traps
- Never PR, push branches or file issues upstream; the maintainer refuses porting patches (see PORTING-PPC.md).
- Never pipe picker acquisition; `| tail` hid a failed claim (see INCIDENTS.md, 2026-09-23).
- PPC deps exist only on mini-intel: use `BUILD_HOSTS=mini-intel`; `BUILD_HOST=` skips the lock (see docs/BUILD-OPERATIONS.md).
- Audit PPC undefined symbols against 10.3.9 before launch; one newer symbol makes dyld abort on a G3 (see PORTING-PPC.md).
- Treat `std::locale` facet calls as PPC crash suspects (see docs/ppc-lessons.md).
- Client tags use `vX.Y.Z`; server tags use `server-vX.Y.Z`; delete old releases without `--cleanup-tag` (see docs/RELEASE.md, BUGFIXES #9).
- qemu-tiger3d: one claim via `pick-bench-host.sh --run`, deploy, smoke, bench and screendump inside it (see docs/VM-TIGER.md).

## Where to look
- Docs → `docs/README.md`
- Build → `docs/BUILD-OPERATIONS.md`, `BUILD-HOST.md`
- Deploy → `docs/BUILD-OPERATIONS.md`, `docs/SHARED-TOOLS.md`
- Smoke → `docs/BUILD-OPERATIONS.md`
- Bench → `docs/BUILD-OPERATIONS.md`
- Tests → `docs/TESTS.md`
- Release → `docs/RELEASE.md`
- Tickets → `docs/TICKETS.md`
- History → `BUGFIXES.md`, `INCIDENTS.md`, `docs/archive/`
- VM → `docs/VM-TIGER.md`
- Server → `SERVER.md`
- Upstream engine docs (Lua, MML, netgame) → `docs/`
