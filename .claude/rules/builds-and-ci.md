# Builds and CI

- **Centralized Source of Truth**: `old-mac-build-host` is the strict, centralized source of truth for all builds, toolchains, and CI workflows. Do not rely on local Jenkinsfiles or legacy CI scripts.
- **CI active and green**: `.github/workflows/ci-build.yml` runs on all pushes/PRs, but overarching build coordination and authoritative CI definitions defer to `old-mac-build-host`.
- **Public repo — the CI-green rule applies**: `--with-catch2` is already wired into the Linux configure step. Ensure builds stay green.
