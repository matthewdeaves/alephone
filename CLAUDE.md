# Aleph One old-Mac port

**Core Goal:** Port Marathon 1/2/Infinity on the current Aleph One engine as ONE fat binary spanning `ppc` (10.3.9 target / 10.4 fallback), `i386` (10.4.4+) and `x86_64` (10.5+). This is a from-scratch build.

## Documentation Router

For situational context, consult the specific rule files in `.claude/rules/`:
- **When dealing with compilation, libraries, or legacy architectures:** Read `.claude/rules/legacy-mac-hardware.md`.
- **When interacting with Git, GitHub issues, or repository specifics:** Read `.claude/rules/repo-specifics.md`.
- **When working on CI/CD or building the project:** Read `.claude/rules/builds-and-ci.md`. *Note: `old-mac-build-host` is the centralized source of truth for builds and CI.*

*ADR Addition:* Consider utilizing Architecture Decision Records (ADR) in `.claude/rules/adr/` or `docs/` to store project information and decisions.

## Read on demand
- `PORTING-PPC.md` — the port plan: target matrix, dependency decisions, toolchain resolution.
- `BUILD-HOST.md` — machine roles, Apple SDK downloads.
- `SERVER.md` — dedicated server investigation findings.
- `BUGFIXES.md` — running log of bug fixes in this fork.

## Working alongside the other repos

This repo is one of eight worked on together: five game ports, the private
`retro-server-infra` which runs the servers, the private `old-mac-build-host`
which owns the machines, and `retro-agents` which runs the sessions. One board
covers all eight: <https://github.com/users/matthewdeaves/projects/8>. Top-level
project goals (PPC/Intel/Apple Silicon, OS X 10.3+, frame rate vs. features) are
the `retro-agents` manager's call, not this repo's; hardware testing spans every
dual-boot OS alias on the G3 and G5 Dual 2.7 machines, not just whichever OS
happens to be booted right now.

Nothing arbitrates WORKING TREES. Two sessions in one repo can collide silently,
and a sync can write into your tree mid-task, so stage by name and never
`git add -A`.

**The board columns are gates, not labels:**

    Triage -> Measuring -> Ready -> In progress -> Blocked -> Review -> Done

`Triage` is the user's gate; only a human moves work out of it. `Measuring` means
approved: work it. STOP AT `Review` — `Done` is the user's, not yours. Write
`Refs #12` in commit messages, never `Closes` or `Fixes`, or GitHub closes the
issue behind your back while the column still says Review.

The shared GitHub account runs on a strict 5000/hr GraphQL budget. Filing an
issue does NOT put it on the board and nothing sets a status on a new item, so
it lands in no column at all and looks like work nobody raised. Run
`retro-agents/bin/board-add.sh <repo>#<n>` after filing, every time, and never
run `gh project item-list`/`item-edit` — those burn the shared GraphQL budget;
`board.sh`/`board-add.sh`/`board-move.sh` are REST and free.

**The full rules are in `retro-agents/briefs/`, not here.** Every session is
launched with them. This section used to be synced verbatim from a canonical
copy (`retro-agents/briefs/SHARED-BLOCK.md`); that sync tool was retired
2026-08-28 (zero adopters fleet-wide, and it never actually covered this repo —
old-mac-build-host#31), so this is now this repo's own hand-maintained copy;
where the briefs and this file differ, the briefs win.
