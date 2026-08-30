# Aleph One — Old Mac Port

A fork of [Aleph One](https://github.com/Aleph-One-Marathon/alephone), the open-source
engine that plays Bungie's *Marathon*, *Marathon 2*, and *Marathon Infinity*. This fork
ports the current engine to run as **one fat binary** on real vintage Macs, from a
PowerPC G3 running Mac OS X 10.3.9 up to a 2019 Intel Mac — not just modern arm64/x86_64.

## Runs on

| Slice    | Minimum OS | Covers                                    |
|----------|------------|--------------------------------------------|
| `ppc`    | 10.3.9     | G3 / G4 / G5 (no AltiVec assumed)          |
| `i386`   | 10.4.4     | Early Intel Macs (Core Duo/Solo) → 10.14   |
| `x86_64` | 10.5+      | Core 2 Duo and later, current macOS        |

One universal binary, one download, all three architectures — matching what Aleph One
itself shipped from 2011–2015 before that build was dropped for unrelated reasons (see
`PORTING-PPC.md`).

## What's different from upstream

- Fat `ppc`/`i386`/`x86_64` build, cross-compiled with a pinned GCC 14 → PowerPC
  toolchain (upstream targets arm64/x86_64 only).
- Dependency versions pinned specifically for old-hardware correctness — e.g. boost
  1.76.0 (not 1.90 — PPC regression) and openal-soft 1.23.1 (not 1.24+ — broken
  AltiVec SIMD on big-endian).
- Real bugs found and fixed on real hardware: PPC toolchain miscompilations, dyld
  weak-symbol collisions with system libraries, and a GPU driver that silently ran
  shaders in software instead of on the GPU. Full write-ups in `BUGFIXES.md`.

## Downloads

Prebuilt DMGs are on the [Releases page](https://github.com/matthewdeaves/alephone/releases).
Game data (Marathon/Marathon 2/Infinity) is included via git submodules — clone with
`--recurse-submodules`, or see upstream's build instructions below for a from-scratch
build.

## How this was built

Development is an automated AI loop, Claude Code under my direction: implement,
build, deploy to real hardware, run it there, iterate. Bugs are found and fixed
against real G3/G4/G5 Macs on Panther, Tiger, and Leopard, using crash reports and
CPU profiling from that hardware. `BUGFIXES.md` logs what broke and how it was
fixed.

## Building from source

Upstream's build instructions (Linux/Windows/vcpkg-based macOS) still apply and are
unchanged — see [the original README](https://github.com/Aleph-One-Marathon/alephone#readme).
For the PPC/Intel fat-binary build specific to this fork, see `PORTING-PPC.md` and
`scripts/build.sh`.

## License

[GPL v3](http://www.gnu.org/licenses/gpl-3.0.html), same as upstream Aleph One.
