# Release namespaces and inputs

## Tags
Client tags are `vX.Y.Z`; server tags are `server-vX.Y.Z`. The collision and first server-package omissions are recorded under #9 in `BUGFIXES.md`.
Delete old releases without `--cleanup-tag`.
Retention and promotion follow the fleet release procedure in POLICY.

## Checks
Package with `scripts/package-dmg.sh`; build, deploy and smoke inputs are in `docs/BUILD-OPERATIONS.md`. PPC symbol checks and engine tests are in `docs/TESTS.md`. `SERVER.md` describes the existing `standalone_hub` server.
