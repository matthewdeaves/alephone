# Aleph One old-Mac port

Marathon 1/2/Infinity on the current Aleph One engine, as ONE fat binary
spanning `ppc` (10.3.9 target / 10.4 fallback), `i386` (10.4.4+) and `x86_64`
(10.5+) — a G3 to a 2019 Mac Pro, one binary. Sticky facts only; the plan
itself lives in `PORTING-PPC.md` and `BUILD-HOST.md` — read both before
touching anything, they are not stale, they are dated 2026-08-21/22 and this
file does not repeat them.

## Where this actually stands (verify against the tree, not this line)

This is a from-scratch build, not a tuning pass like the other four ports.
As of 2026-08-23: no `scripts/` directory, no PPC cross-compiler on any fleet
machine, no fat binary, nothing benched. Do not assume `PORTING-PPC.md`'s
checkboxes are current — it is a living plan doc, check the tree.

Two open items block a first build:
- Whether `SDL_GameController` works on PPC at all — every existing fleet
  SDL2 tree (`panther-sdl2`, `leopard-sdl2`) is built `--disable-joystick`.
- The GCC 14 cross-compiler itself. Not built anywhere yet.
  `old-mac-build-host` owns installing it (`from:port`, don't self-bootstrap
  against a shared box) — precedent: `remote-build-gcc-snow.sh` (GCC 7.5,
  Snow Leopard).

## Facts that would otherwise need re-deriving

- **SDL2 floor is 2.0.3, not 2.0.16.** AO calls zero APIs newer than 2.0.3;
  the one exception (`SDL_SoftStretchLinear`) already falls back to
  `SDL_BlitScaled`. The existing fleet trees (`panther-sdl2` 2.0.3 10.3.9,
  `leopard-sdl2` 2.0.6 10.5) already satisfy it — **no SDL2 fork needed.**
- **Six deps to port**, everything else `--without-*`'d off: SDL2, SDL2_ttf,
  boost **1.76.0** (not 1.90 — PPC regression, boostorg/atomic#79), asio
  (header-only), libsndfile, **openal-soft 1.23.1** (not 1.24+ — broken
  AltiVec SIMD on big-endian). Apple's `OpenAL.framework` cannot substitute:
  `OpenALManager::Init` hard-requires `ALC_SOFT_loopback` and EFX, neither of
  which Apple's framework has.
- **GCC 14, pinned.** GCC 15 silently broke on Tiger PPC (PR 123976); GCC 16
  dropped flags Callahan's bootstrap recipe depends on. LLVM/clang has no PPC
  backend at all — not a candidate.
- **The weak-linking trap is the governing risk**, not compile failure: link
  one 10.4-only symbol and the build passes on the host, then dyld aborts at
  *launch* on a 10.3.9 G3. `nm -arch ppc -u` against the 10.3.9 symbol set is
  mandatory before claiming any PPC target works — for every linked binary,
  not just the main app.
- **Runtime feature detection, not per-machine tuning.** One `ppc` slice at
  the lowest reachable deployment target; GL 2.0 / IOHIDManager / gamepads
  light up by runtime check on Leopard rather than raising the floor. This is
  the same shape the other four ports' briefs require — audit config
  generation against it.
- **This exact artifact shipped for four years** (AO 1.0–1.2.1, 2011–2015,
  3-way `ppc i386 x86_64` fat, `LSMinimumSystemVersion 10.4.0`) and was
  dropped for SDL2 alone, not endianness or the C++ standard — recoverable
  from git history (`8042f4f2`, `PBProjects/` pre-deletion, and the Tiger
  GLSL `DisableClipVertex()` workaround at `release-20150620`).

## Repo specifics

- Fork of `Aleph-One-Marathon/alephone`. `upstream` remote push is disabled.
  Never PR, push a branch, or file an issue upstream — upstream's maintainer
  said in writing they will not take patches from porting projects. This is
  explicitly *permitted* by them, just never upstreamed.
- **This is a real GitHub fork of an active repo, so bare `gh issue list` /
  `gh issue view` resolve to `Aleph-One-Marathon/alephone` (580+ unrelated
  issues), not this fork.** Verified 2026-08-23 — `gh repo view` confirms
  `isFork: true`. Always pass `-R matthewdeaves/alephone` explicitly. This is
  the one repo in the fleet where the shared brief's "bare `gh issue list`
  reads the git remote and cannot get the name wrong" does not hold — the
  other four ports aren't forks of a live upstream.
- **Public repo — the CI-green rule applies.** `.github/workflows/ci-build.yml`
  builds Linux/Windows/macOS on `[push, pull_request]`, no branch filter.
  `--with-catch2` is already wired into the Linux configure step.
- Scenario data (three Marathon games) are submodules under `data/Scenarios/`.
  This repo ships code, same content rule as the other four ports.
- `tests/` + Catch2 (`replay_film_test.cpp`) is the existing verification
  oracle for endian/replay correctness — use it, don't build a parallel one.
- No `scripts/` directory yet. When one exists, raise fleet tooling
  (bench lock, host picker) with `old-mac-build-host` as `from:port` rather
  than writing a sixth hand-rolled copy.

## Working alongside the other repos

This repo is one of eight worked on together: five game ports, the private
`retro-server-infra` which runs the servers, the private `old-mac-build-host`
which owns the machines, and `retro-agents` which runs the sessions. One board
covers all eight: <https://github.com/users/matthewdeaves/projects/8>.

Nothing arbitrates WORKING TREES. Two sessions in one repo can collide silently,
and a sync can write into your tree mid-task, so stage by name and never
`git add -A`.

**The board columns are gates, not labels:**

    Triage -> Measuring -> Ready -> In progress -> Blocked -> Review -> Done

`Triage` is the user's gate; only a human moves work out of it. `Measuring` means
approved: work it. STOP AT `Review` — `Done` is the user's, not yours. Write
`Refs #12` in commit messages, never `Closes` or `Fixes`, or GitHub closes the
issue behind your back while the column still says Review.

Filing an issue does NOT put it on the board and nothing sets a status on a new
item, so it lands in no column at all and looks like work nobody raised. Run
`retro-agents/bin/board-add.sh <repo>#<n>` after filing, every time.

**The full rules are in `retro-agents/briefs/`, not here.** Every session is
launched with them. This block is the short version for a human reading this repo
cold; where the two differ, the briefs win.

## Read on demand

- `PORTING-PPC.md` — the port plan: target matrix, dependency decisions,
  toolchain resolution, SDL2 investigation, OpenGL ceiling, open questions.
- `BUILD-HOST.md` — machine roles, Apple SDK downloads, the GCC 14 bootstrap
  recipe on Tiger.
