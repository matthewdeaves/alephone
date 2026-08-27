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

<!-- retro-shared-block: canonical copy lives in retro-agents/briefs/SHARED-BLOCK.md.
     Do not edit this region in a port repo; it is overwritten by the sync.

     Everything here must be true of EVERY repo it lands in, which is why it is
     SHORT. Text that has to hold for eight repos converges on the weakest claim,
     so anything that matters MORE to one repo than another is deliberately left
     out and stays in that repo's own words, outside these markers. Claiming Mac
     hardware is the clearest case: it is most of what a port does and one of the
     eight has no scripts/ directory at all. -->

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

<!-- end retro-shared-block -->
