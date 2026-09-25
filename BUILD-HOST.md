# Build host setup — PowerPC toolchain

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

## Machine roles

| Machine | OS | Role |
|---|---|---|
| mini-intel (Core 2) | Lion 10.7 | Builds `ppc` (GCC 14 cross, 10.3.9 SDK) and `x86_64` (GCC 7.5, 10.6 floor) |
| mini-intel2 (Core 2) | Lion 10.7 | Builds `i386` (GCC 14 i686 cross, 10.4u SDK; deps via `scripts/build-deps-i386.sh`) |
| imac-2019 | macOS 15 | Builds the i386 SDL2 (`scripts/build-sdl2-i386.sh`: Apple clang, 10.4u SDK) |
| G3 / G4 mini / G5 | 10.3.9–10.5.8 | Test targets; Panther is where the 10.3.9 weak-linking trap bites |
| Core 2 minis, imac-2019 | 10.6–15 | Intel test targets (`i386` via `arch -i386` on 10.6/10.7) |
| Workstation (Apple Silicon) | current | Builds `arm64` natively; fuses slices with `llvm-lipo`; packages the DMG |

**Do NOT install Xcode on the Panther machines.** Everything targets 10.3.9 through
the 10.3.9 SDK from Xcode 2.5; Panther boxes are test targets only.

## From Apple (developer.apple.com/download/all/, free Apple ID)

1. **Xcode 2.5** — `xcode25_8m2558_developerdvd.dmg` — **essential**.
   Last Xcode for Tiger. Provides GCC 4.0.1 (bootstrap seed), **MacOSX10.3.9.sdk +
   MacOSX10.4u.sdk**, and cctools. Tigerbrew requires it.
   After install verify: `ls /Developer/SDKs` should list both SDKs.
2. **Xcode 3.2.6** — `xcode_3.2.6_and_ios_sdk_4.3.dmg` — only if an Intel Mac runs 10.6.
   Last Xcode with PPC support; 10.4u/10.5/10.6 SDKs.
3. **Xcode 3.1.4** — `xcode314_2809_developerdvd.dmg` — only if building on Leopard.

If a download 404s, `xcodereleases.com/data.json` has current URLs.

## GCC 14 bootstrap on Tiger (Callahan's verified recipe, 2025-03)

There is **no prebuilt GCC bottle** for Tiger PPC. This must be built. Sequence:

1. Install **Xcode 2.5**.
2. Install **Tigerbrew** (`mistydemeo/tigerbrew`, actively maintained — commits Aug 2026).
3. From Tigerbrew get **GCC 4.2.1**, **`ld64-97.17`**, **`cctools-806`**.
   - `ld64-97.17` **replaces** Xcode 2.5's `ld` — GCC needs ld64-85.2.1+ and Xcode 2.5's
     is too old. (ld64-97 is also reported to work better on PPC than ld64-127.)
   - `cctools-806` is the last cctools supporting Tiger PPC.
4. **Patch the cctools-806 assembler** to ignore `-mmacosx-version-min=` and
   `.macosx_version_min` directives — modern GCC emits these by default and the old
   assembler rejects them. *This is a required patch, not optional.*
5. **Build bash 5.x and install as both `/bin/bash` and `/bin/sh`.** Tiger's bash 2.05b
   is insufficient for modern GCC configure scripts. *Do this before the bootstrap.*
6. Staged bootstrap, each stage built **without self-bootstrapping** to save time:
   **4.2.1 → 4.7.4 → 9.5.0 → 14.2.0**
   - 4.7.4 = last version bootstrappable with ISO C89
   - 9.5.0 = recommended intermediate with stable C++17
7. Statically embed **gmp, mpfr, libmpc, isl** into the final GCC 14.2.0 for portability.
8. Install to a prefix such as `/opt/gcc14` (Callahan's choice) to avoid disturbing
   the system toolchain.

Reference: https://briancallahan.net/blog/20250329.html

Pin **GCC 14**. GCC 15 silently broke on Tiger PPC (PR 123976); GCC 16 removed
`--with-gnu-as`/`--with-gnu-ld` (commits `786cab9c4`, `69d23b515`, July 2026),
untested for darwin8 — and Callahan's recipe depends on `--with-as=`/`--with-ld=`.

## Not from Apple — open source, we fetch these

- Tigerbrew — `github.com/mistydemeo/tigerbrew`
- GCC 14.2.0 — gcc.gnu.org
- SDL **2.0.22** — last pre-ARC release
- `alex-free/panther-sdl2` (2.0.3, 10.3.9+10.4) and `leopard-sdl2` (2.0.6, 10.5)
- Thomas Bernard's `SDL2-2.0.3_OSX_104.patch` — upstream of both
- `macports-legacy-support` — backfills POSIX/libc gaps on 10.4/10.5
- `macos-powerpc/powerpc-ports` — boost 1.76, openal-soft 1.23.1, libsndfile etc.

## Verification after setup

    /opt/gcc14/bin/gcc --version          # expect 14.2.0
    /opt/gcc14/bin/gcc -v 2>&1 | grep Target   # expect powerpc-apple-darwin8
    echo 'int main(){return 0;}' > /tmp/t.c
    /opt/gcc14/bin/gcc -mmacosx-version-min=10.3 -isysroot /Developer/SDKs/MacOSX10.3.9.sdk /tmp/t.c -o /tmp/t
    otool -hv /tmp/t                      # confirm PPC Mach-O
    nm -u /tmp/t                          # undefined symbols must all exist on 10.3.9

The `nm -u` check is the guard against the weak-linking trap: a 10.4-only symbol here
means dyld aborts at launch on a Panther G3, while every test passes on the build host.
