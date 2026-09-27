# Repository Specifics

- Fork of `Aleph-One-Marathon/alephone`. `upstream` remote push is disabled. Never PR, push a branch, or file an issue upstream — upstream's maintainer said in writing they will not take patches from porting projects (explicitly *permitted*, just never upstreamed).
- Use bare `gh issue`/`gh pr` from inside this repo — it resolves to this fork correctly (re-verified 2026-09-27). Don't pass `-R`: the guard hook blocks it outright.
- Scenario data (three Marathon games) are submodules under `data/Scenarios/`. This repo ships code, same content rule as the other four ports.
- `tests/` + Catch2 (`replay_film_test.cpp`) is the existing verification oracle for endian/replay correctness — use it, don't build a parallel one.
- `scripts/` (build, package-dmg, deploy-dmg, smoke-dmg, pick-bench-host, pick-build-host, etc.) largely mirrors `old-mac-quakespasm`'s fleet tooling shape. Raise gaps or divergence with `old-mac-build-host` as `from:port` rather than hand-rolling a fix here.
- **Client release tags are `vX.Y.Z` (semver)** — replacing the old ad-hoc `release-YYYYMMDD-fat-N` scheme (historical tags stay, don't rename them). Server releases keep their own `server-vX.Y.Z` stream. Give each release a real name in its GitHub Release title, not the bare tag.
- Pruning old client releases (POLICY's release flow) also has the guard hook blocking `--cleanup-tag` — deleting the release itself, without that flag, is the allowed path (confirmed live 2026-09-25).
