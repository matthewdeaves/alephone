---
paths:
  - "scripts/build*.sh"
  - "scripts/*deps*.sh"
  - ".github/workflows/*.yml"
---

# Builds and CI

- `old-mac-build-host` is the centralized source of truth for builds, toolchains and CI — don't rely on local Jenkinsfiles or legacy CI scripts.
- `.github/workflows/ci-build.yml` runs on all pushes/PRs; `--with-catch2` is wired into the Linux configure step. Keep it green.
