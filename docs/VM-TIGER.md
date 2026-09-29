# Tiger VM renderer profile

On qemu-tiger3d, use the existing classic OpenGL renderer. The September 27,
2026 comparison found approximately 0.1 fps with GLSL on both cold and warm
runs. A guest `sample` placed the work in Apple's `gldFPEmulateScanline` and
`PPEmulatorRun`. Metal shader caching did not remove this driver fallback.

With `ALEPHONE_FORCE_CLASSIC_GL=1`, the Marathon 2 L00 film at 1024x768
reached 56.6–60.7 fps after its first logging window, with world ticks
advancing. Normal Finder launch also rendered correctly, confirmed visually
by the user. These are VM observations, not physical Radeon certification.

The shared build-host deployment hook detects the QEMU device-tree node and
adds this environment variable to the installed app's `LSEnvironment`, keeping
other entries. Physical machines keep their existing selection rules. Both
benchmark entry points use the same VM default; set
`ALEPHONE_BENCH_FORCE_CLASSIC=0` to investigate GLSL again.

Local evidence: `~/oldmac/evidence/solo-vm-20260927/`, including
`solo-alephone-classic.log`, `alephone-classic.png`, and
`solo-ao-guest-sample.txt`. The emulator defect remains tracked at
[matthewdeaves/qemu#10](https://github.com/matthewdeaves/qemu/issues/10).

Builds, shared deployment, and CI remain owned by `old-mac-build-host`.
No game binary or real-hardware renderer defaults changed for this profile.

## One-claim iteration

Run `scripts/shared.sh pick-bench-host.sh --run qemu-tiger3d "<label>" -- <script>` with a driver that performs `deploy-dmg.sh`, `smoke-dmg.sh`, `bench-evidence.sh` and `qemu-vm.sh screendump <png>` through `scripts/shared.sh`.
Set `BENCH_ARTEFACT=<staged binary>` and `BENCH_ADAPTER=scripts/bench-adapter.sh` for evidence. Stage the artifact locally before the run; it must be the binary being measured. Shared VM procedure: `../old-mac-build-host/docs/qemu-vm.md`.
