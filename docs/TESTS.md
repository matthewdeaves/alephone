# Test entry points

## Engine tests
`tests/replay_film_test.cpp` supplies Catch2 endian and replay tests. `.github/workflows/ci-build.yml` runs on pushes and PRs; the Linux configure step enables them with `--with-catch2`.

## PPC and runtime checks
`scripts/check-ppc-symbols.sh` audits linked binaries against the 10.3.9 SDK. Use `nm -arch ppc -u` for the undefined-symbol inspection. `docs/BUILD-OPERATIONS.md` maps installed smoke and benchmark tools.
