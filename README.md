# Aleph One — Old Mac Port

A fork of [Aleph One](https://github.com/Aleph-One-Marathon/alephone), the open-source
engine that plays Bungie's *Marathon*, *Marathon 2*, and *Marathon Infinity*. This fork
ports the current engine to run as **one fat binary** spanning a PowerPC G3 running
Mac OS X 10.3.9 all the way up to a current Apple Silicon Mac.

## Runs on

| Slice    | Minimum OS | Covers                                    |
|----------|------------|--------------------------------------------|
| `ppc`    | 10.3.9     | G3 / G4 / G5 (no AltiVec assumed)          |
| `i386`   | 10.4.4     | Core Solo / Core Duo Macs (see below)      |
| `x86_64` | 10.6       | Core 2 Duo and later, current macOS (declared 10.5, see below) |
| `arm64`  | 11.0       | Apple Silicon (M1 and later)               |

One universal binary, one download. Two declared targets are not fully proven yet.
They are tracked, not dropped:

- **`i386` is built for 10.4.4 but has only run on 10.7** ([#30](https://github.com/matthewdeaves/alephone/issues/30)).
  The test fleet has no Intel Mac running 10.4 or 10.5.
- **`x86_64` needs 10.6, not 10.5** ([#31](https://github.com/matthewdeaves/alephone/issues/31)).
  Same gap: no Intel Mac running 10.5 to test on.

**Tested for v1.2.0** on real hardware: G3 (10.3.9, 10.4.11), G4 Mac mini (10.4.11),
G5 (10.3.9, 10.4.11, 10.5.8), Core 2 Mac minis (10.6.8, 10.7.5; `i386` via `arch -i386`),
a 2019 iMac (macOS 15) and an M5 Mac (macOS 26); played by hand on the G3 and G5.
No 32-bit-only Core Solo/Duo Mac, or Intel Mac on 10.4/10.5, is in the fleet.

**Known issues:** early Intel Macs with GMA 950 graphics are slow (about 7 fps in
the Marathon 2 demo on a Core 2 Mac mini, using classic OpenGL).

## What's different from upstream

- Fat `ppc`/`i386`/`x86_64`/`arm64` build in one binary (upstream ships arm64/x86_64
  as separate downloads, with no PowerPC or 32-bit Intel). `ppc` and `i386`
  cross-compile with pinned GCC 14 toolchains, `x86_64` with GCC 7.5, and `arm64`
  builds natively.
- Hardware OpenGL by default on every supported Mac. GPUs without shader support,
  or measured too slow with it (Radeon 9600, GMA 950), use the classic
  fixed-function renderer. First-run graphics defaults come from the GL
  capabilities found at runtime. The software renderer remains a manual option
  and the fallback if no GL context can be created.
- Host or join a network game through your own private dedicated server, not just
  the official public server list — see `SERVER.md` (deployment lives in
  [retro-server-infra](https://github.com/matthewdeaves/retro-server-infra)).
- Pinned dependencies: boost 1.76.0 (1.90 regresses on PPC) and openal-soft 1.23.1
  (1.24+ has broken AltiVec SIMD on big-endian).
- Fixes for bugs found on real hardware are listed in `BUGFIXES.md`.

## Downloads

Prebuilt DMGs are on the [Releases page](https://github.com/matthewdeaves/alephone/releases).
Game data (Marathon/Marathon 2/Infinity) is included via git submodules — clone with
`--recurse-submodules`, or see upstream's build instructions below for a from-scratch
build.

## Building from source

Upstream's build instructions (Linux/Windows/vcpkg-based macOS) still apply and are
unchanged — see [the original README](https://github.com/Aleph-One-Marathon/alephone#readme).
For the PPC/Intel/Apple Silicon fat-binary build specific to this fork, see
`PORTING-PPC.md`, `scripts/build.sh`, and `scripts/build-arm64.sh`. Test-fleet installs use
buildhost's shared `deploy-dmg.sh`/`smoke-dmg.sh` (pinned via `shared-scripts.pin`,
run through `scripts/shared.sh`), configured by `scripts/dmg-port.conf`.

## License

[GPL v3](http://www.gnu.org/licenses/gpl-3.0.html), same as upstream Aleph One.
