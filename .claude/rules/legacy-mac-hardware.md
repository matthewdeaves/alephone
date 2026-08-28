# Legacy Mac Hardware & Porting Facts

- **SDL2 floor is 2.0.3, not 2.0.16.** AO calls zero APIs newer than 2.0.3; the one exception (`SDL_SoftStretchLinear`) already falls back to `SDL_BlitScaled`. The existing fleet trees (`panther-sdl2` 2.0.3 10.3.9, `leopard-sdl2` 2.0.6 10.5) already satisfy it — **no SDL2 fork needed.**
- **Six deps to port**, everything else `--without-*`'d off: SDL2, SDL2_ttf, boost **1.76.0** (not 1.90 — PPC regression, boostorg/atomic#79), asio (header-only), libsndfile, **openal-soft 1.23.1** (not 1.24+ — broken AltiVec SIMD on big-endian). Apple's `OpenAL.framework` cannot substitute: `OpenALManager::Init` hard-requires `ALC_SOFT_loopback` and EFX, neither of which Apple's framework has.
- **GCC 14, pinned.** GCC 15 silently broke on Tiger PPC (PR 123976); GCC 16 dropped flags Callahan's bootstrap recipe depends on. LLVM/clang has no PPC backend at all — not a candidate.
- **The weak-linking trap is the governing risk**, not compile failure: link one 10.4-only symbol and the build passes on the host, then dyld aborts at *launch* on a 10.3.9 G3. `nm -arch ppc -u` against the 10.3.9 symbol set is mandatory before claiming any PPC target works — for every linked binary, not just the main app.
- **Runtime feature detection, not per-machine tuning.** One `ppc` slice at the lowest reachable deployment target; GL 2.0 / IOHIDManager / gamepads light up by runtime check on Leopard rather than raising the floor. This is the same shape the other four ports' briefs require — audit config generation against it.
- **This exact artifact shipped for four years** (AO 1.0–1.2.1, 2011–2015, 3-way `ppc i386 x86_64` fat, `LSMinimumSystemVersion 10.4.0`) and was dropped for SDL2 alone, not endianness or the C++ standard — recoverable from git history (`8042f4f2`, `PBProjects/` pre-deletion, and the Tiger GLSL `DisableClipVertex()` workaround at `release-20150620`).
- **PPC C++17 cross-compiler landed (`old-mac-build-host#25`):** GCC 14.2.0 targeting `powerpc-apple-darwin8` is built and verified at `/Users/mini/gcc14-ppc` on `mini-intel`, using intermediate host GCC 7.5.0 and `cctools-port`. Target `libstdc++-v3` and `libgcc` compiled cleanly against `MacOSX10.3.9.sdk`. Real hardware verified on `mini-g4` (Tiger 10.4.11) with static `nm -u` symbol acceptance against 10.3.9 `libSystem`. Toolchain blocker is resolved.

## Operational lessons, 2026-08-28 (from chasing three real crashes to real fixes on real hardware)

- **A PPC binary can crash by calling INTO the wrong `libstdc++`, even with
  `-static-libstdc++ -static-libgcc` and zero declared dylib dependency on
  it.** Leopard's own `AudioToolbox`/`CoreAudio`/`OpenGL` frameworks each
  transitively link `/usr/lib/libstdc++.6.dylib`, and this cross-toolchain's
  linker was satisfying some out-of-line libstdc++ symbols (e.g.
  `std::basic_istream<char>::operator>>`) from that reachable dynamic
  re-export instead of the static archive — two ABI-incompatible C++
  runtimes' RTTI/locale objects colliding is an indirect call into garbage
  (`EXC_BAD_INSTRUCTION`, `ctr` register pointing at data, not code). Fix is
  `-Wl,-force_load` on the toolchain's own `libstdc++.a`/`libgcc.a`, not more
  `-static-*` flags. If a future PPC crash's live crash-reporter Binary
  Images list shows a system dylib you never linked, check what your
  *frameworks* transitively pull in with `otool -L` before assuming it's an
  app bug — `-static-libstdc++` alone does not guarantee it.
- **`std::locale`-facet virtual dispatch is specifically dangerous on this
  toolchain.** `boost::property_tree::iptree`'s default comparator
  (`less_nocase`) and its `stream_translator` (typed value extraction, used
  for every XML attribute) both go through `std::locale` facets internally —
  both crashed independently, same signature. Treat ANY `std::locale`-facet
  call (not just these two) as suspect on PPC until this toolchain issue is
  actually root-caused upstream; a locale-free reimplementation is a safe,
  narrow workaround per call site (see `scripts/patches/`).
- **Build host deps are host-specific, not interchangeable, even though
  `pick-build-host.sh`'s picker treats every candidate in `BUILD_HOSTS` as
  equally usable.** The PPC/Intel toolchains and dependency prefixes
  (`/Users/mini/gcc14-ppc`, `/Users/mini/alephone-ppc-deps`,
  `/Users/mini/alephone-intel-deps`) exist only on `mini-intel`, not
  `mini-intel2` — a plain `./scripts/build.sh ppc` grabs whichever candidate
  is free first and fails cryptically (`ln: .../include/SDL2: No such file
  or directory`) if it lands on the wrong one. When a specific host's state
  matters (a patch you just applied there, a toolchain that only lives
  there), force it with `BUILD_HOSTS=mini-intel` before `--acquire`/
  `build.sh`, not `BUILD_HOST=` directly (that bypasses the lock entirely —
  measured hitting a peer's in-progress build on `mini-intel` this way; use
  `BUILD_HOSTS` to *restrict the candidate list*, which still queues and
  waits properly).
- **A launch-matrix "PASS" from checking process liveness at a fixed short
  timeout is not proof of a working launch.** `imac-g5` showed
  `PROCESS: alive` at both 6s and 10s checks while a 100%-reproducible SIGILL
  was actually landing within that same window on a slower run — the
  process being alive at your checkpoint says nothing about what happens a
  few seconds either side of it. Real evidence is the live crash reporter
  (`~/Library/Logs/CrashReporter/*.crash` on Panther/Tiger/Leopard,
  `~/Library/Logs/DiagnosticReports/*.crash` on Snow Leopard and later) or a
  human's own eyes, not a background-and-kill script's exit status.
- **A remote diagnostic-capture script over `ssh ... << 'HEREDOC'` has two
  independent gotchas that both look like "it just doesn't work" until you
  isolate them:** (1) appending `</dev/null` on the same line as a heredoc
  replaces the heredoc as the command's stdin instead of adding to it — ssh
  delivers an empty script, exit 0, zero output, nothing to debug from. Only
  redirect stdin away from a backgrounded *child process launched inside*
  the heredoc, never from the outer `ssh` command that carries the heredoc.
  (2) A backgrounded child that inherits ssh's stdin/stdout/stderr keeps the
  whole `ssh` call from returning until that child exits, defeating
  backgrounding entirely — redirect all three FDs on the child's own launch
  line (`cmd < /dev/null > out 2>&1 &`). Separately: libc fully block-buffers
  stdout when it isn't a tty, so a plain `printf`/`cout` from a killed
  (not exited) process can be silently lost even with correct redirection —
  wrap the target command in `script -q /dev/null <cmd>` to give it a pty
  and force line-buffering if you need to see that output before the process
  would otherwise exit.
