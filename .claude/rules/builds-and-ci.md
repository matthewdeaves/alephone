---
paths:
  - ".github/workflows/*.yml"
---

# CI

- `.github/workflows/ci-build.yml` runs on all pushes and PRs; `--with-catch2` is wired into the Linux configure step. Keep it green.
