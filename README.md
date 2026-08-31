# Aleph One — Old Mac Port

A fork of [Aleph One](https://github.com/Aleph-One-Marathon/alephone), the open-source
engine that plays Bungie's *Marathon*, *Marathon 2*, and *Marathon Infinity*. This fork
ports the current engine to run as **one fat binary** spanning a PowerPC G3 running
Mac OS X 10.3.9 all the way up to a current Apple Silicon Mac.

## Runs on

| Slice    | Minimum OS | Covers                                    |
|----------|------------|--------------------------------------------|
| `ppc`    | 10.3.9     | G3 / G4 / G5 (no AltiVec assumed)          |
| `i386`   | 10.4.4     | Early Intel Macs (Core Duo/Solo) → 10.14   |
| `x86_64` | 10.5+      | Core 2 Duo and later, current macOS        |
| `arm64`  | 11.0+      | Apple Silicon (M1 and later), current macOS |

One universal binary, one download, all four architectures. The `ppc`/`i386`/`x86_64`
trio matches what Aleph One itself shipped from 2011–2015 before that build was dropped
for unrelated reasons (see `PORTING-PPC.md`); `arm64` is new here. Unlike the other
three, it isn't legacy-constrained — it's built natively and tracks the engine's
current dependency versions rather than the old pins the other slices need.

## What's different from upstream

- Fat `ppc`/`i386`/`x86_64`/`arm64` build in one binary (upstream ships arm64/x86_64
  as separate downloads, no PowerPC or 32-bit Intel at all). `ppc`/`i386`/`x86_64`
  cross-compile with a pinned GCC 14 → PowerPC toolchain; `arm64` builds natively.
- Real hardware-accelerated OpenGL by default on every supported Mac, G3 and up —
  including GPUs with no shader support at all (falls back to the classic
  fixed-function GL path, still on the GPU) and GPUs whose driver falsely claims
  shader support it can't actually run in hardware. A software renderer is still
  available as a manual option (Preferences → Graphics) or automatic last-resort
  fallback if OpenGL context creation fails outright, same as upstream.
- Host or join a network game through your own private dedicated server, not just
  the official public server list — see `SERVER.md`.
- Dependency versions pinned specifically for old-hardware correctness — e.g. boost
  1.76.0 (not 1.90 — PPC regression) and openal-soft 1.23.1 (not 1.24+ — broken
  AltiVec SIMD on big-endian).
- Real bugs found and fixed on real hardware: PPC toolchain miscompilations, dyld
  weak-symbol collisions with system libraries, and a GPU driver that silently ran
  shaders in software instead of on the GPU. Full write-ups in `BUGFIXES.md`.

## Dedicated server

Details on hosting your own game (the client feature above) are in `SERVER.md`.
The actual server deployment/infra lives in the separate
[retro-server-infra](https://github.com/matthewdeaves/retro-server-infra) repo.

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
For the PPC/Intel/Apple Silicon fat-binary build specific to this fork, see
`PORTING-PPC.md`, `scripts/build.sh`, and `scripts/build-arm64.sh`.

## License

[GPL v3](http://www.gnu.org/licenses/gpl-3.0.html), same as upstream Aleph One.
