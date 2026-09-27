# Aleph One old-Mac port

**Core Goal:** Port Marathon 1/2/Infinity on the current Aleph One engine as ONE fat binary spanning `ppc` (10.3.9 target / 10.4 fallback), `i386` (10.4.4+) and `x86_64` (10.5+). This is a from-scratch build.

## Read on demand
- `.claude/rules/legacy-mac-hardware.md` — compilation, dependencies, legacy architectures (auto-loads for build scripts and engine source).
- `.claude/rules/repo-specifics.md` — this fork's Git/GitHub specifics.
- `.claude/rules/builds-and-ci.md` — CI (auto-loads for build/CI files).
- `.claude/rules/adr/` or `docs/` — architecture decisions, if any are recorded.
- `PORTING-PPC.md` — port plan: target matrix, dependency decisions, toolchain resolution.
- `BUILD-HOST.md` — machine roles, Apple SDK downloads.
- `SERVER.md` — dedicated server investigation findings.
- `BUGFIXES.md` — running log of bug fixes in this fork.

## Repo-specific traps not covered by fleet POLICY.md
- Two sessions can collide silently in this working tree, and a sync can write into it mid-task — stage by name, never `git add -A`.
- This repo's hardware testing scope spans every dual-boot OS alias on the G3 and G5 Dual 2.7 machines, not just whichever OS happens to be booted right now.

Board flow, releases, evidence rules and decide-don't-ask are fleet-wide and live in `retro-agents/POLICY.md` (every session's system prompt) and `retro-agents/briefs/` — not duplicated here. Where they and this file differ, POLICY wins.
