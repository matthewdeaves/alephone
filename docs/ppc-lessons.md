# PPC crash and tooling lessons

Four lessons from chasing real PPC crashes and remote-diagnostic failures (2026-08-28).
Read the section that matches your symptom; build facts live in `.claude/rules/ppc-facts.md`.

## Wrong libstdc++ on Leopard
- Symptom: `EXC_BAD_INSTRUCTION`, `ctr` pointing at data, despite `-static-libstdc++ -static-libgcc`.
- Cause: Leopard's AudioToolbox, CoreAudio and OpenGL link `/usr/lib/libstdc++.6.dylib`. The linker took some symbols (e.g. `std::basic_istream<char>::operator>>`) from that re-export, not the static archive. Two C++ runtimes' RTTI and locale objects then collide.
- Fix: `-Wl,-force_load` on the toolchain's own `libstdc++.a` and `libgcc.a`.
- Check: a crash report listing a system dylib you never linked means `otool -L` your frameworks.

## std::locale facets crash on this toolchain
- `boost::property_tree::iptree` (`less_nocase`) and its `stream_translator` (every XML attribute) crashed independently, same signature.
- Treat any `std::locale`-facet call as suspect on PPC. A locale-free reimplementation per call site is the safe workaround (`scripts/patches/`).

## Build hosts are not interchangeable
- PPC and Intel toolchains and deps (`/Users/mini/gcc14-ppc`, `~/oldmac/alephone/{ppc,intel}-deps`) exist only on `mini-intel`, not `mini-intel2`.
- A plain `./scripts/build.sh ppc` lands on whichever host is free and fails with `ln: .../include/SDL2: No such file`.
- Use `BUILD_HOSTS=mini-intel`: it restricts the candidate list and still queues. `BUILD_HOST=` bypasses the lock (it hit a peer's build).

## Launch checks and remote capture
- A "PASS" from process liveness at 6s and 10s is not proof: `imac-g5` showed alive while a reproducible SIGILL landed just after. Use the crash reporter (`~/Library/Logs/CrashReporter/*.crash` on 10.3-10.5, `DiagnosticReports/` from 10.6) or eyes on the screen.
- `ssh ... << 'EOF' </dev/null` replaces the heredoc: empty script, exit 0. Redirect stdin only on a backgrounded child inside the heredoc.
- A backgrounded child inheriting ssh's fds stops ssh returning: `cmd < /dev/null > out 2>&1 &`.
- Non-tty stdout is block-buffered, so a killed process loses its output: wrap in `script -q /dev/null <cmd>`.
