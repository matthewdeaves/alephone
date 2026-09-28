# Aleph One — PPC / Intel Fat Binary Port

Current decisions for the fat binary: target matrix, pinned dependencies, the SDL2 requirement,
the Tiger .app bundle and the weak-linking gate. The investigation trail behind them (toolchain
bootstrap, SDL2 fork, endian audit, precedent) is in `docs/porting-history.md`.
Never PR, push a branch or file an issue upstream; the `upstream` remote's push URL is disabled.

## Target matrix

| Slice    | Min OS  | Covers                                              |
|----------|---------|-----------------------------------------------------|
| `ppc`    | **10.3.9** target / 10.4 fallback | All PPC Macs — G3, G4, G5 (baseline, **no AltiVec**) |
| `i386`   | 10.4.4  | 2006 Core Duo/Solo → 10.14 Mojave                    |
| `x86_64` | 10.5+   | Core 2 Duo → current macOS on Intel                  |

Added, 2026-08-31 (alephone#17): **arm64**, as a fourth slice alongside the
three below. Unlike ppc/i386/x86_64, arm64 carries none of this project's
legacy-toolchain or big-endian constraints, so it deliberately tracks
upstream's current engine and current dependency versions instead of the
pinned ones the table above documents. Built natively on the fleet's one
Apple Silicon Mac (`scripts/build-arm64.sh`, run on `workstation` per
`old-mac-build-host` docs/apple-silicon-arm64.md), never cross-compiled.
Fused into the same universal binary as the other three by `scripts/build.sh
fat`, as an OPTIONAL slice — a fat build produced anywhere other than
`workstation` still succeeds with just ppc+x86_64, matching how every other
port in this fleet already treats its own arm64 slice.

Deliberately excluded:
- **ppc64** — a G5 runs the `ppc` slice at full speed; adds a slice and a test
  target for no user-visible gain.
- **ppc7400** (AltiVec) — optional *later* as a 4th slice for G4/G5 speed. The
  baseline `ppc` slice must stay G3-safe, so AltiVec can never be assumed.

Why both Intel slices: the first Intel Macs (Core Duo/Solo, Yonah) are 32-bit only
and can never run x86_64. Catalina 10.15 dropped 32-bit entirely. So i386 covers the
old end, x86_64 the new end — complements, not redundancy. They also split the
debugging variables: x86_64 = known-good control, i386 = isolates wordsize bugs on
fast hardware, ppc = adds endianness as the only new variable.

## Dependency decisions

Only **six** deps must be ported to PowerPC. Everything else is switched off.

| Keep (must port)      | Note                                          |
|-----------------------|-----------------------------------------------|
| SDL2                  | Hardest. Engine needs SDL2-only APIs (below)  |
| SDL2_ttf              |                                               |
| boost                 | Sets the real C++ floor, not Aleph One        |
| asio                  | Header-only                                   |
| libsndfile            |                                               |
| OpenAL                | Ships in the OS as OpenAL.framework from 10.4 |
| Catch2                | Kept deliberately — the verification oracle   |

Switched off:
`--without-vpx --without-matroska --without-ebml --without-libyuv --without-nfd`
`--without-curl --without-zzip --without-miniupnpc --without-sdl_image --disable-steam`

That removes libvpx, libmatroska/libebml, libyuv, steamworks and
nativefiledialog-extended — every genuinely hostile dependency. Film/movie export
does not ship on PPC; it never existed in the PPC era anyway.

`--disable-opengl` gives a software-renderer-only build. Start there; GL is a later
stretch goal (PPC-era GPUs cap around GL 2.0).

## SDL2 is mandatory — SDL 1.2 will not do

The engine uses SDL2-only APIs: `SDL_CreateWindow`, `SDL_CreateRenderer`,
`SDL_Texture`/`SDL_RenderCopy`, `SDL_GL_CreateContext`/`SetAttribute`/`SwapWindow`,
`SDL_GameController*`, `SDL_Keycode`/`SDL_Scancode`, `SDL_StartTextInput`,
`SDL_SetRelativeMouseMode`, `SDL_SetWindowFullscreen`, `SDL_GetWindowWMInfo`.
366 distinct SDL symbols in total.

## .app bundle for Tiger

- **Icons already work.** Our `.icns` files carry `it32`+`t8mk` (128×128 = the 10.3/10.4
  maximum). No regeneration needed. Only if rendering misbehaves, strip the 10.7-era
  `TOC ` chunk that sits first in `AlephOne.icns`.
- **Set `INFOPLIST_OUTPUT_FORMAT=XML`** — currently unset, so Xcode emits binary plists.
- **Set per-arch deployment targets** using the mechanism already used for arm64:
  `MACOSX_DEPLOYMENT_TARGET[arch=ppc]=10.4`, `[arch=i386]=10.4`, `[arch=x86_64]=10.5`.
- `LSMinimumSystemVersion` is currently `10.13` — must change.
- **Do not code-sign the retro build.** Unsigned is correct for 10.4/10.5. (PPC slices
  *do* sign fine on modern tooling if ever needed — verified — but signing adds a
  10.5-era `LC_CODE_SIGNATURE` of unverified tolerance, for zero benefit.)
- Must be absent: `_CodeSignature`, `Assets.car` (10.9+, icon genuinely won't be found),
  `Base.lproj` (10.8+ — use `English.lproj`).
- Genuine PPC-era binaries carry **no** `LC_VERSION_MIN_MACOSX` (that's 10.6+). Its
  absence in our output is correct, not a bug.

## Weak-linking gotcha

Building against 10.4u but deploying lower links 10.4-only symbols **strongly**; dyld
then aborts at **launch** with "Symbol not found" — on the target machine, passing every
test on the build host. Use `AvailabilityMacros.h` (10.2-era; `Availability.h` is 10.6+
and irrelevant here) and compare function **addresses** to `NULL`. `-isysroot` +
`-mmacosx-version-min` must appear in `CFLAGS`, `CXXFLAGS` **and** `LDFLAGS`.

