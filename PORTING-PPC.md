# Aleph One — PPC / Intel Fat Binary Port

Goal: build the **current** Aleph One engine as a **single fat binary** running on
every Mac from a 2003 G3 to a 2019 Intel Mac Pro.

**This is a private fork. Never open PRs, push branches, or file issues upstream
(Aleph-One-Marathon/alephone). The `upstream` remote has its push URL disabled.**

## Target matrix

| Slice    | Min OS  | Covers                                              |
|----------|---------|-----------------------------------------------------|
| `ppc`    | 10.3.9  | All PPC Macs — G3, G4, G5 (baseline, **no AltiVec**) |
| `i386`   | 10.4.4  | 2006 Core Duo/Solo → 10.14 Mojave                    |
| `x86_64` | 10.5+   | Core 2 Duo → current macOS on Intel                  |

Deliberately excluded:
- **arm64** — already supported upstream, explicitly out of scope.
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

## Source audit (completed)

Good news — the engine's own code is in far better shape than expected:

- **32-bit clean.** Zero pointer→int casts. Only 2 pointer-size references, both
  benign (`POINTER_DATA` is a real `byte *`, RenderVisTree.h:47).
- **Zero SIMD.** No SSE/NEON/AltiVec intrinsics anywhere.
- **Trivial threading.** 1 `std::thread`, 1 `std::mutex`, 12 `std::atomic`.
- **Tiny C++17 surface**: 22 `std::optional`, 4 structured bindings,
  2 `[[fallthrough]]`, 1 variadic template, 0 `if constexpr`, 0 inline variables,
  0 `std::filesystem` (uses boost's). A C++17→C++11 backport is a small diff.
- **C++11 is pervasive** and non-negotiable: 675 `auto`, 163 `nullptr`,
  137 `unique_ptr`, 129 range-`for`, 60 `override`, 48 `= default`, lambdas,
  `enum class`, raw strings. **GCC 4.2 supports none of it** — so Xcode 3's own
  compiler cannot build this. That is the central toolchain constraint.
- Big-endian scaffolding survives: `ALEPHONE_LITTLE_ENDIAN` (cseries.h:46),
  `byte_swap_memory` (byte_swapping.h), BStream/AStream. Unexercised since ~2011.

Size: 270k lines total, 248k excluding bundled Lua.

## Toolchain

Constraint: we need a compiler that emits **PPC Mach-O** *and* supports **C++11+**.
Apple never shipped one — Xcode 3.2.6 (last with PPC) tops out at GCC 4.2 / C++03.

Planned shape: use Xcode 3.2.6 / cctools for what it's uniquely good at — PPC-capable
`as`, `ld`, `lipo`, the 10.4u SDK, and bundle packaging — but swap in a **modern GCC**
as the compiler, wired in via an External Build System target or a custom `.xcspec`.

*Exact GCC version pending research.* Do not guess.

## Verification strategy

`tests/replay_film_test.cpp` + recorded films for M1, M2 and Infinity. Film replay is
deterministic lockstep: if a PPC build replays the films to the same end state as an
x86_64 build, the endian port is provably correct. This is the oracle — it means the
byte-swapping work is testable rather than eyeballed. Keep Catch2 for this reason.

Build order: x86_64 (control) → i386 (wordsize) → ppc (endianness).

## Open questions

- [ ] Which GCC can target `powerpc-apple-darwin` with C++11/17? (researching)
- [ ] Is 10.3 achievable or is 10.4 the practical floor? (researching)
- [ ] SDL2 on PPC — existing patches, or port it ourselves? (researching)
- [ ] Boost: newest version that builds for PPC Darwin? (researching)
- [ ] QEMU (`qemu-system-ppc`, Mac99) as a fast test target vs real G3/G4/G5?
