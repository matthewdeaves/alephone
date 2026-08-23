# Aleph One — PPC / Intel Fat Binary Port

Goal: build the **current** Aleph One engine as a **single fat binary** running on
every Mac from a G3 running Tiger to a 2019 Intel Mac Pro.

**This is a private fork. Never open PRs, push branches, or file issues upstream
(Aleph-One-Marathon/alephone). The `upstream` remote has its push URL disabled.**

## Target matrix

| Slice    | Min OS  | Covers                                              |
|----------|---------|-----------------------------------------------------|
| `ppc`    | **10.3.9** target / 10.4 fallback | All PPC Macs — G3, G4, G5 (baseline, **no AltiVec**) |
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

## Toolchain — RESOLVED

**LLVM/clang is a dead end.** Apple clang has no PowerPC backend at all
(`clang --print-targets` lists 11 backends, none PowerPC); modern `ld` self-reports
no ppc. Iain Sandoe's own 2016 LLVM RFC proposed removing PowerPC/Darwin as
perpetually incomplete. **Use GCC.**

**GCC 14 is the answer**, targeting `powerpc-apple-darwin8` (10.4) or `darwin9` (10.5):
- GCC still carries `powerpc-*-darwin*` and `powerpc-apple-darwin8` is in
  `contrib/config-list.mk`, GCC's cross-build smoke test.
- Brian Callahan bootstrapped **GCC 14.2.0 natively on a 1.25GHz G4 under Tiger**
  (2025-03), then built Python 3.12 / OpenSSL 3.3.2 / curl 8.11 with it.
- `macos-powerpc/powerpc-ports` ships **GCC 14.3.0** with Tiger patches, actively
  maintained (commits within the last week).
- GCC 15/16 on PPC are unvalidated upstream — GCC 15 silently broke on Tiger PPC
  (PR 123976). **Pin GCC 14.**

**10.3.9 is the target; 10.4 is the documented fallback.** Iain Sandoe deleted
`powerpc-darwin7` from config-list.mk in 2023-09 (`594fe7457`), noting *"GCC will no
longer build with native tools."* Read precisely, that is about **bootstrapping GCC on
Panther**, not about *targeting* it — `config.gcc` still handles `darwin7`, and
`alex-free/panther-sdl2` explicitly supports **10.3.9** with
`MACOSX_DEPLOYMENT_TARGET=10.3` (tested with Xcode 2.5).

Approach: cross-GCC + lowest achievable `-mmacosx-version-min`, one `ppc` slice,
runtime feature detection above it — the pattern AO itself used in
`DisableClipVertex()`. **The governing risk is the weak-linking trap:** link a single
10.4-only symbol and dyld aborts *at launch* on a 10.3.9 G3, while every test passes on
the build host. Audit with `nm -arch ppc -u` against the 10.3.9 symbol set before
declaring 10.3 support. If the runtime proves unreachable, fall back to 10.4 and say so
plainly rather than shipping something that dies on a G3.

**Binutils:** Tiger's Xcode 2.5 tools are insufficient — GCC needs **ld64-85.2.1+**.
Use Tigerbrew's `ld64-97.17` / `cctools-806` (ld64-97 is reported to work better on
PPC than ld64-127), or `tpoechtrager/cctools-port` branch `877.8-ld64-253.9-ppc`
(Michael Weiser's PPC forward-port, updated 2026-04).

**SDK:** 10.4u via `devel​​ernay/xcodelegacy` (`XcodeLegacy.sh`, v2.7 July 2026) which
also patches the 10.4u SDK to work with GCC 4.2+. Xcode 3.2.6 is the last Apple
release with PPC support (10.4u + 10.5 + 10.6 SDKs).

**`lipo`: a non-problem — verified empirically.** Xcode 26.6's `lipo` is cctools-1040
and retains full PowerPC support (create / thin / extract / verify / `-detailed_info`,
plus `otool`, `nm`, `size`, `strip`, `install_name_tool` with `-arch ppc`). Use Apple's
own current `lipo` to fatten. **Never pass `-fat64`** — XNU rejects `FAT_MAGIC_64` for
`MH_EXECUTE`; it can't happen accidentally for an app binary.

**Fat binaries are safe by construction.** XNU `bsd/kern/mach_fat.c` `fatfile_getarch()`
`continue`s past any cputype it doesn't recognise. A Tiger G4 sees the i386/x86_64
slices, doesn't match them, and loads `ppc`. Adding slices can never break older ones.
The fat header and every `fat_arch` are always big-endian regardless of host.

## SDL2 — SOLVED (was believed to be the critical path)

**RESOLVED 2026-08-21. Aleph One's real SDL floor is 2.0.3, not 2.0.16 — and Matt's
existing `panther-sdl2` tree already provides exactly that.**

Measured, not reasoned: AO calls **zero** APIs from SDL 2.0.4/2.0.5/2.0.6. Its only
post-2.0.3 API is `SDL_SoftStretchLinear` (ScenarioChooser.cpp:526), already wrapped in
`#if SDL_VERSION_ATLEAST(2,0,16)` with an `SDL_BlitScaled` (2.0.0) fallback. The only
other version guards are two `SDL_MOUSEWHEEL_FLIPPED` sites (shell.cpp:1365,
sdl_widgets.cpp:1659) — cosmetic scroll-direction, degrades gracefully. All four
`SDL_HINT_*` used are 2.0.0–2.0.2.

`configure.ac:167` has been lowered to `sdl2 >= 2.0.3` accordingly. **No SDL fork,
no de-ARC pass, no 2.0.22 backport is needed.** Use the existing fleet trees:
`~/oldmac/panther-sdl2` (2.0.3, 10.3.9, G3) and `~/oldmac/leopard-sdl2` (2.0.6, 10.5).

Historical note — the ARC cliff below still matters if we ever *do* need newer SDL2:

**There are TWO cliffs, not one.** Measured 2026-08-21 by fetching
`src/video/cocoa/SDL_cocoawindow.m` at each tag (reproducible in ~20s):

| tag | `__bridge` | `release]` | build system |
|---|---|---|---|
| 2.0.3 | 0 | 26 | autotools: no `-fobjc-arc` |
| 2.0.6 / 2.0.16 / 2.0.22 | 0 | 6 | CMake *does* pass `-fobjc-arc`; **autotools does not** |
| **2.24.0** | **38** | 0 | CMake unconditional; configure probes |
| 2.26.0 / 2.30.0 | 39 | 0 | **2.30.0** adds `FATAL_ERROR` |

1. **Source-level ARC adoption is 2.24.0** — this is the cliff that blocks GCC, and the
   mechanism is the *source* using ARC constructs, not the build refusing.
2. **The hard `FATAL_ERROR` is 2.30.0**, a separate and later event.

*Correction: an earlier draft attributed the `FATAL_ERROR` to 2.24.0. It is 2.30.0.*
Note also that 2.0.22's **CMake** path already passes `-fobjc-arc`, so grepping for that
flag places the cliff in the wrong release — use the **autotools** path on PPC.

Ceiling is unchanged: **2.0.22 is the last release usable by a non-ARC PPC compiler.**
Still unmeasured by anyone: that a GCC PPC build of 2.0.22 actually compiles and runs.
Do not record "2.0.22 works on PPC" until someone does it.

**Viable window: SDL 2.0.16 – 2.0.22.** AO's configure requires `sdl2 >= 2.0.16`;
**2.0.22 (2022-04-25) is the last pre-ARC release.** Base the fork on 2.0.22.

Do NOT use MacPorts upstream `libsdl2-powerpc` (2.30.10): it is **X11-only**, built
`--disable-video-cocoa --disable-video-opengl --disable-joystick`, and on Tiger also
`--disable-audio`. Unusable for Aleph One.

Prior art to build from:
- `alex-free/panther-sdl2` — SDL **2.0.3**, 10.3.9 + 10.4, real Cocoa backend
- `alex-free/leopard-sdl2` — SDL **2.0.6**, 10.5, real Cocoa backend
- Thomas Bernard's `SDL2-2.0.3_OSX_104.patch` (855 lines/16 files) — upstream of both
- MacPorts `0001-Fixes-for-PowerPC.patch` — mechanical `@autoreleasepool` →
  `NSAutoreleasePool` de-ARC across all `.m` files (proves de-ARC is mechanical)
- SDL commit `4a468739f` (2016-05-21) removed 10.5 support — **revert it** to recover
  Apple's own `CGDisplayAvailableModes` path verbatim

Known gap: **joystick/GameController is disabled in every existing PPC SDL2 build**
(10.4 lacks `IOHIDManager`; MacPorts hits GCC ICE PR105522 in hidapi). Aleph One uses
`SDL_GameController`. On 10.5 it *should* build (IOHIDManager is 10.5+), but this is
**unproven** — treat as a real risk. 2.0.16 predates hidapi and sidesteps the ICE.

## OpenGL reality on PPC

| OS | GPU | GL | Shaders |
|---|---|---|---|
| Tiger 10.4 | anything | **max GL 1.5**, no NPOT on *any* GPU | ARB frag shaders on R3xx+/NV3x+ |
| Leopard 10.5 | Radeon 9600+/GeForce FX+ | **GL 2.0 + GLSL 1.20**, NPOT | yes |
| either | Radeon 9200 | GL 1.3 | **never** — fixed function only |

Start `--disable-opengl` (software renderer). GL is a Leopard-only stretch goal
requiring R3xx/NV3x or better. AO's GL path uses `glCreateShaderObjectARB` and never
calls `glewInit()` off Windows — ARB shader objects are exactly what these GPUs expose.

## Dependencies — mostly solved by an existing ecosystem

`macos-powerpc/powerpc-ports` (MacPorts fork, 25k+ ports, 759 prebuilt, release
2026.07) already carries working ppc/ppc64 darwin8/9 ports of nearly everything:

| Dep | Version | Note |
|---|---|---|
| boost | **1.76.0** | Boost.Atomic has native PPC asm → lockfree works. **Avoid 1.90** (PPC regression, boostorg/atomic#79) |
| SDL2 | fork 2.0.22 | See above — the real work |
| SDL2_ttf | 2.24.0 | pure C + FreeType, easy |
| asio | 1.32.0 | header-only |
| libsndfile | 1.2.2 | BE-clean by construction (reads AIFF) |
| **openal-soft** | **1.23.1 — MANDATORY** | see below |
| Catch2 | 3.15.3 | our oracle |

**CORRECTION — Apple's OpenAL.framework CANNOT substitute.** `OpenALManager::Init`
(OpenALManager.cpp:46-58) hard-fails without **`ALC_SOFT_loopback`**; AO never opens a
real device, it renders via `alcRenderSamplesSOFT` into `SDL_OpenAudio`, and
`GenerateEffects()` needs **EFX** (`alGenFilters`, `AL_FILTER_LOWPASS`). Apple's
framework has neither. openal-soft **1.23.1** specifically — 1.24.0+ added AltiVec SIMD
that is broken on big-endian (kcat/openal-soft#1067).

Compile out, confirmed zero-cost:
- **nativefiledialog** — AO already has an in-engine `ReadFileDialog`
  (FileHandler.cpp:1477) used whenever `HAVE_NFD` is undefined; every call site guarded
- **steamworks** — Steam for Mac was Intel-only 10.5+; the *client* never ran on PPC
- **FILM_EXPORT** (vpx+matroska+ebml+vorbis+libyuv) — all-or-nothing gate. libvpx
  deleted PPC support upstream in 2015; its only PPC SIMD since is VSX/POWER8, which
  no Apple PowerPC machine has. Dropping this removes 4 risky deps at once.
- **libyuv** — has a BE-aware path but zero PPC SIMD; AO falls back to pl_mpeg

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

## Open questions

- [x] ~~Which GCC?~~ **GCC 14**, `powerpc-apple-darwin8/9`
- [x] ~~Is 10.3 achievable?~~ **No. 10.4 is the floor.**
- [x] ~~SDL2 on PPC?~~ **Fork 2.0.22** (last pre-ARC); prior art exists
- [x] ~~Boost version?~~ **1.76.0**, avoid 1.90
- [x] ~~Tiger or Leopard?~~ **Lowest floor + runtime detection.** Leopard buys GL 2.0,
      IOHIDManager (joystick), working CoreAudio, ObjC 2.0. Tiger buys older G3s.
      **DECIDED: neither — target the lowest, detect features at runtime.** Must run
      on 10.3, 10.4, 10.5, 10.6, 10.7 and up, PPC and Intel. So the `ppc` slice takes
      the lowest reachable deployment target and lights up GL 2.0 / IOHIDManager /
      gamepads by runtime check on Leopard, rather than raising the floor.
      Note Leopard officially requires an 867MHz G4+, so a 10.5 floor would drop the
      G3s outright — hence the low floor plus runtime detection.
- [x] ~~Does `SDL_GameController` work at all on PPC?~~ **RESOLVED 2026-08-23: not a
      build blocker.** Read from both sides' source. SDL2's public joystick/controller
      API compiles unconditionally (`configure.in:333` adds `src/joystick/*.c` to every
      build; `--disable-joystick` only adds the dummy backend at `configure.in:3091`
      and defines `SDL_JOYSTICK_DISABLED`) — so AO links fine against the fleet's
      `--disable-joystick` trees. The failure is at **runtime**: `SDL_InitSubSystem`
      returns an error for `SDL_INIT_JOYSTICK`/`SDL_INIT_GAMECONTROLLER` when disabled
      (panther-sdl2 `src/SDL.c:207,220`), and AO's `shell.cpp:236-248` passes those
      flags in one combined `SDL_Init` and calls `exit(1)` on any failure — video and
      audio fine, dead at launch anyway. Two outs: AO already has `-j`/`--nojoystick`
      (`shell_options.cpp:95`) which skips the flags entirely; or a small fallback in
      `initialize_application` (retry `SDL_Init` without the joystick flags on
      failure), which is the runtime-detection shape this port wants — gamepads light
      up automatically iff the SDL2 slice supports them. `initialize_joystick()` and
      the rest of `joystick_sdl.cpp` are safe with the subsystem absent: guarded by
      `SDL_NumJoysticks() <= 0` / `active_instances.empty()`. Whether gamepads can be
      made to *work* on 10.5 (IOHIDManager) is a separate, later question — the game
      runs either way.
- [ ] **THE remaining blocker: a C++17 compiler for PPC.** The fleet's PPC toolchain is
      `gcc-4.0`/`gcc-4.2` from Xcode 3.2.6 (C++03) — fine for Quake/Half-Life, which are
      C; cannot build AO's C++17. Needs GCC 14 cross to `powerpc-apple-darwin`, hosted
      on a Lion mini or `mini-sl`, reusing the existing 10.3.9/10.4u/10.5 SDKs and
      Xcode 3.2.6 cctools. Precedent in Matt's own fleet:
      `old-mac-build-host/scripts/remote-build-gcc-snow.sh` already builds GCC 7.5 on
      Snow Leopard.
- [ ] QEMU (`qemu-system-ppc`, Mac99) as a fast test target vs real G3/G4/G5?
- [ ] Big-endian bit-rot survey (5th agent still running)

## Precedent

No one has published a genuine 2020s ppc+i386 fat Mach-O. ScummVM ships a current
"Mac OS X 10.4+ PPC 32 bits" build but as a *separate download*. TenFourFox's 2020
"Super Duper Universal Binary" post is explicitly theoretical — *"there's a challenge
for someone."* **We would be doing something genuinely novel.** Every mechanical piece
is verified to work.

## Precedent — corrected: we are REBUILDING something that existed

The exact artifact we want **shipped for four years**. Aleph One 1.0 (2011-12-01)
through **1.2.1 (2015-06-20)** were all 3-way fat binaries — `ppc i386 x86_64`,
`LSMinimumSystemVersion 10.4.0` — verified by `lipo` on the archived DMGs. 1.2.1
remained the official stable download until 1.3 shipped in Aug 2020.

Published 1.0 requirements (inherited by 1.2.1): *500 MHz / 128 MB RAM; 1 GHz /
256 MB recommended. Mac OS X 10.4 or higher. OpenGL (Shader) renderer: ATI Radeon
9600 or nVidia GeForce FX 5200 or newer.* Note this matches the GL capability data
exactly — and it means **the Shader renderer genuinely ran on PPC**.

PPC and i386 were dropped together at **1.3a1 (2015-09-07)**. `8042f4f2`
(2015-03-12, Hopper, "Ensure correct architectures are built in Xcode 3.2") had set
`ARCHS = (ppc, i386, x86_64)` only three months earlier — PPC was actively defended,
then dropped for a stated reason:

> treellama, 2016-01-12: *"The new SDL uses APIs that simply aren't available in
> ancient versions of OS X."*

**The drop was SDL2, not the C++ standard, not endianness.** That is exactly the
blocker this plan is built around, and it confirms the SDL2 fork is the critical path.

### Recoverable from git history

- `git show release-20150620:Source_Files/RenderMain/OGL_Shader.cpp` — the **Tiger
  GLSL workaround**: `DisableClipVertex()` sniffs `uname -r` for `"8."` because
  *"In Mac OS X 10.4 and Mesa, setting gl_ClipVertex causes a black screen."*
  Deleted from master by `3a148ecd`. **Revert it** when GL is attempted.
- `git show 8042f4f2` — the Xcode 3.2 project settings that produced the 3-way fat.
- `PBProjects/` (the Xcode 2/3 project) was deleted by `efe39821` (2016-02-28) —
  fully recoverable.

### Upstream's own position — validates keeping this private

> Hopper (lead maintainer), 2016-01-24: *"I have no objection to anyone porting
> future Aleph One versions to PowerPC or other unsupported systems, similar to the
> TenFourFox project... **However, I will not accept patches from porting projects
> which make it harder to maintain and improve Aleph One for supported systems.**"*

So the port is explicitly *permitted* and upstream has explicitly said they will not
take the patches. Nobody has taken it up in the ten years since. Keep this fork private
to upstream — that is their stated preference, not just ours.

## The big de-risk: modern Aleph One already builds big-endian

**FreeBSD ships a built package of Aleph One 1.6.1 (`alephone-20230119_3`) for 32-bit
big-endian `powerpc`.** ([freshports.org/games/alephone](https://www.freshports.org/games/alephone/))

That is a post-SDL2, post-C++17 Aleph One (Jan 2023) compiling and packaging on a
big-endian PowerPC target *today*. It does not prove it renders correctly, and it was
built with libyuv/libvpx enabled — exercising the very movie-export path most likely
to be endian-broken. But it substantially de-risks the C++ and endianness side.

**Conclusion: the blocker is the macOS platform stack (SDL2, the 10.13 target, vcpkg,
GLSL), not the engine and not big-endianness.** The film-replay oracle still has to
prove endian correctness, but we are no longer guessing whether it's achievable.
