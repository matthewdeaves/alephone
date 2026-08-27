# Repository Specifics

- Fork of `Aleph-One-Marathon/alephone`. `upstream` remote push is disabled. Never PR, push a branch, or file an issue upstream — upstream's maintainer said in writing they will not take patches from porting projects. This is explicitly *permitted* by them, just never upstreamed.
- **This is a real GitHub fork of an active repo, so bare `gh issue list` / `gh issue view` resolve to `Aleph-One-Marathon/alephone` (580+ unrelated issues), not this fork.** Verified 2026-08-23 — `gh repo view` confirms `isFork: true`. Always pass `-R matthewdeaves/alephone` explicitly. This is the one repo in the fleet where the shared brief's "bare `gh issue list` reads the git remote and cannot get the name wrong" does not hold — the other four ports aren't forks of a live upstream.
- Scenario data (three Marathon games) are submodules under `data/Scenarios/`. This repo ships code, same content rule as the other four ports.
- `tests/` + Catch2 (`replay_film_test.cpp`) is the existing verification oracle for endian/replay correctness — use it, don't build a parallel one.
- No `scripts/` directory yet. When one exists, raise fleet tooling (bench lock, host picker) with `old-mac-build-host` as `from:port` rather than writing a sixth hand-rolled copy.
