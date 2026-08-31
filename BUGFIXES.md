# Bug fixes

One short entry per real bug fixed in this fork: what it was, what the fix was.
Newest first.

- **PPC/Leopard on ATI R300-class cards: shader renderer unplayably slow
  (~0.5fps) despite the driver reporting full GLSL support** (alephone#16).
  Reported repeatedly on real `imac-g5` hardware (ATI Radeon 9600/RV351)
  while the same build "played lovely" on `mini-g4` (older GPU, correctly
  falls back to the classic renderer). Two real, separate contributors,
  found in that order:
  1. `RenderRasterize_Shader::render_node_floor_or_ceiling` and
     `render_viewer_sprite` drew with `GL_POLYGON`, a primitive type badly
     supported on legacy hardware, `sample`-profiled at real gameplay time
     landing 28% of samples in Apple's software-rendering-plugin fallback
     (`gleFallbackBegin`). Fixed by switching to `GL_TRIANGLE_FAN`/
     `GL_QUADS` (commit 675a0ea6). This helped (user-confirmed: "a little
     bit better") but did not fix the actual problem — the dominant cost
     was elsewhere.
  2. The real dominant cost, found by re-profiling real gameplay with fix
     #1 already applied: `RenderRasterize_Shader::render_node_object`
     (drawing every in-world sprite — monsters, items, weapons) uses a real
     GLSL shader (`Shader::S_Sprite` etc. via `setupSpriteTexture`). Apple's
     Leopard-era ATI R300 driver advertises `GL_ARB_fragment_shader` /
     `GL_ARB_shading_language_100` and passes every capability check the
     game does at startup — but at *runtime* it silently executes that
     shader through a software LLVM interpreter
     (`gldLLVMFPTransformFallback` -> `glvmInterpretFPTransformFour`) one
     fragment at a time instead of on the GPU. `sample` showed ~15% of
     render-thread time in that single call chain; the "sort by top of
     stack" summary was dominated by `glvm*`/LLVM-register-allocator
     symbols, not game code. There is no portable way to query "will this
     GPU actually run my shader in hardware" in advance — extension
     presence says nothing about it. Fixed in `screen.cpp`'s renderer setup
     with a targeted `GL_RENDERER` string match ("Radeon 9600") that forces
     the classic fixed-function renderer (`Rasterizer_OGL_Class`/
     `OGL_Render.cpp`, dormant since 2009 but still fully wired up and, on
     this exact driver, genuinely hardware-accelerated) instead of the
     shader renderer. Verified three ways on real `imac-g5` hardware: (a) a
     fresh 30s gameplay `sample` after the fix shows zero
     `gldLLVMFPTransformFallback`/`glvmInterpretFPTransformFour` hits, with
     the render thread now mostly idle/waiting rather than pegged; (b) the
     same result with the renderer forced manually via
     `ALEPHONE_FORCE_CLASSIC_GL=1` (kept as a diagnostic override for
     testing other suspect GPUs, since more R300-family parts — 9500/9700/
     9800, X300-X800 — are plausible candidates for the same bug but are
     NOT confirmed and deliberately not blocklisted without the same kind
     of real-hardware measurement); (c) the user's own real playtest,
     first "still not playable" with only fix #1, then "totally playable"
     and "playing lovely" with fix #2, both with and without the env var
     forcing it.

- **PPC/Leopard: two separate 100%-reproducible SIGILL crashes on every
  launch** (alephone#11), found chasing "human double-click launch
  unreliable" (alephone#5) onto real `imac-g5` (10.5.8) hardware. Both
  confirmed via the live macOS crash reporter's own Binary Images list
  (authoritative — not offline symbolication against a possibly-mismatched
  slice), both reproduced independently by an automated test and by the
  user's own manual Finder launch (identical crash address both times), both
  verified fixed by a 15s+ direct run on the real machine afterward.
  1. `boost::property_tree::iptree`'s default comparator (`less_nocase`)
     calls `std::toupper(ch, locale)` — a virtual dispatch through a
     `std::locale` facet. This PPC/GCC14 cross-toolchain miscompiles that
     indirect call: the crashed thread's `ctr` register (PPC's indirect-call
     target) pointed into `__cxxabiv1::__class_type_info` RTTI data instead
     of real code. Every MML/XML config file load goes through this
     (`InfoTree : iptree`), so every game hit it on Leopard. Fixed with a
     locale-free ASCII `toupper()` in the header-only comparator
     (`scripts/patches/boost-1.76.0-less_nocase-no-locale.patch`, applied by
     both `build-deps-ppc.sh` and `build-deps-intel.sh` right after boost's
     headers are staged, so it survives a from-scratch dependency rebuild).
  2. A second, related crash immediately followed the first fix:
     `std::basic_istream<char>::operator>>(short&)` (via
     `boost::property_tree`'s `stream_translator`, used for every typed XML
     attribute) — same virtual-dispatch-into-garbage signature. Root cause,
     confirmed by checking which loaded image the crash PC actually fell in:
     Leopard's own `AudioToolbox`/`CoreAudio`/`OpenGL` frameworks (all three
     required, no way around linking them) each transitively link the
     *system* `/usr/lib/libstdc++.6.dylib` (verified with `otool -L` against
     each framework on real hardware). Despite `-static-libstdc++
     -static-libgcc`, some libstdc++ symbol references were still resolving
     into that reachable dynamic copy instead of our static archive — two
     ABI-incompatible C++ runtimes' RTTI/locale objects crossing that
     boundary. Fixed with `-Wl,-force_load` on the toolchain's own
     `libstdc++.a`/`libgcc.a`, so every symbol in both becomes part of the
     binary unconditionally and there's no unresolved reference left for the
     system dylib to satisfy.
  **Not fully resolved**: after both fixes, direct launch on `imac-g5` now
  survives past both crash points but shows repeated `malloc: *** error ...
  Non-aligned pointer being freed` warnings. Same symptom class this ticket
  was originally opened for (Marathon Infinity malloc corruption on
  mini-g4/quicksilver's software-renderer path), now also seen on Marathon 1
  on PPC/Leopard. Didn't crash the process in a 15s test window, but this is
  real memory corruption, not resolved — separate investigation needed,
  likely a genuine PPC struct-alignment/big-endian bug given the pattern.

- **x86_64 slice: `dyld: Library not loaded` on every machine that isn't the
  build host** (alephone#5), found on `imac-2019` (Sequoia) — the actual P0
  launch target, not a synthetic test. The x86_64 slice dynamically links
  `libSDL2-2.0.0.dylib` via a bare build-host-absolute path
  (`/Users/mini/oldmac/sdl2-x86_64/lib/...`) — every other dependency
  (`SDL2_ttf`, boost, asio, `libsndfile`, `openal-soft`) statically links; only
  SDL2 itself is a pre-existing shared-lib tree referenced by
  `--with-sdl-prefix`. Worked by pure coincidence on any machine that
  happened to share that exact directory layout (e.g. the build host itself),
  crashed at launch everywhere else. Fixed: `build.sh` fetches the actual
  `.dylib` alongside the compiled x86_64 binary and retargets its load
  command to `@executable_path` on the **thin** slice, before `lipo` — Apple's
  current `install_name_tool` cannot parse this PPC cross-compiled slice's
  load commands at all (`malformed load command 0 (cmdsize is zero)`) and
  aborts on the whole fat binary once ppc is lipo'd in, so the retarget has
  to happen before that point, not after in `package-dmg.sh`.
  `package-dmg.sh` bundles the retargeted `.dylib` into each app's
  `Contents/Frameworks/`, matching the same self-contained shape quakespasm
  ships `SDL.framework` in.

- **`package-dmg.sh`'s version-string collision between client and server
  tags** (alephone#9). `git describe --tags --always --dirty` picks the
  nearest tag by commit ancestry regardless of namespace — once
  `server-v1.0.0` (alephone#9) landed on the same commit as a client DMG
  build, a bare `git describe` named the *client* DMG
  `Marathon-OldMac-server-v1.0.0.dmg`. Fixed by restricting each script's
  `git describe --match` pattern to its own tag namespace
  (`release-*`/`v[0-9]*` for the client, `server-v*` for the server).

- **First server-v1.0.0 release shipped with no systemd unit and a fabricated
  CLI usage doc** (alephone#9) — caught by `retro-server-infra` before
  deploying, not after. `README.txt`'s `-p/-n/-m/-g` flags never existed;
  real usage (measured from `standalone_hub_main.cpp`) is one positional
  port number, nothing else. Added a real `systemd/alephone-server.service`
  to the tarball, deliberately **without** the console-FIFO-on-fd-3 pattern
  the other four ports' units use: `standalone_hub`'s main loop never reads
  stdin at all (measured, full read of the source) — wiring a FIFO anyway
  would silently discard everything written to it, exactly the false-success
  packaging pattern infra's deploy tooling exists to catch. Also not
  self-hosting: a real Aleph One client must still complete a GUI-only
  "gatherer" handshake before any match starts; nothing scripts that today.

- **DMGs built by `package-dmg.sh` could not be mounted at all on real 10.3.9
  Panther hardware** (`hdiutil: attach failed - no mountable file systems`)
  (alephone#5, alephone#7). `hdiutil create` with no explicit `-layout`
  defaults to GPT (protective MBR + GUID partition table) on any reasonably
  modern build host (verified on macOS 26.x here) — GPT postdates every
  PowerPC Mac; it was introduced for the first Intel Macs in 2006. Tiger
  10.4+ can read GPT (it had to, to support early Intel Macs), which is
  exactly why this went unnoticed until testing landed on a real G3 running
  Panther. Fix: `hdiutil create ... -layout SPUD`, which is hdiutil's name
  for the classic Apple Partition Map. Verified mounting on real 10.3.9
  hardware before and after the fix (fails/succeeds respectively), and that
  Tiger and later still mount it fine.

- **Every DMG this pipeline built was software-renderer-only, on every architecture** (alephone#6).
  `scripts/build.sh` hardcoded `--disable-opengl` for both the ppc and x86_64
  configure invocations. Not a PPC-only issue: this forced software rendering
  fleet-wide regardless of GPU. Fix: drop the flag, let configure auto-detect.

- **PPC cross-compile broke once OpenGL was enabled: CoreFoundation pulled in
  `dispatch/dispatch.h`, which doesn't exist pre-10.6** (alephone#6).
  `configure.ac`'s Darwin OpenGL block hardcodes `-F/System/Library/Frameworks`
  (the build host's own absolute path), which shadows the target SDK's own
  frameworks during cross-compilation and pulls in the *host's* modern
  `CoreFoundation.framework` instead of the 10.3.9 SDK's. Verified empirically
  that plain `-isysroot` (already in the build flags) resolves SDK frameworks
  correctly on its own — removed the explicit path entirely.

- **PPC link failed once OpenGL was enabled: `GL_EXT_framebuffer_object` and
  several GL2 shader-status symbols don't exist in the MacOSX10.3.9 SDK's
  linkable stub** (alephone#6). They post-date that SDK. Fixed two ways:
  `OGL_Shader.cpp` mixed ARB-suffixed shader calls (which the 10.3.9 stub
  does export) with plain GL2 core calls for status/error-log queries (which
  it doesn't) — switched those to the consistent ARB names
  (`glGetObjectParameterivARB`/`glGetInfoLogARB`/`glDeleteObjectARB`), which
  is a real correctness fix independent of PPC (mixing ARB object handles
  with core-GL2 entry points is undefined behavior generally, it happened to
  work on newer SDKs by luck). `OGL_FBO.cpp`'s `EXT_framebuffer_object` calls
  have no such ARB predecessor to fall back to, so those are now resolved at
  runtime via `SDL_GL_GetProcAddress` with a safe no-op fallback — which also
  closes a latent crash: `Rasterizer_Shader.cpp` constructs an `FBOSwapper`
  unconditionally with no capability check at all, so any GPU/driver
  genuinely lacking the extension was one segfault away regardless of SDK
  target.

- **PPC cross-build could non-deterministically try to regenerate
  `aclocal.m4`/`configure` with `aclocal-1.18`, which isn't installed on the
  build host** (alephone#6, hit while testing). `rsync` doesn't preserve
  autotools' required dependency-order mtimes between `configure.ac` and its
  generated output, and without `AM_MAINTAINER_MODE` the regen rules are
  always live. Fixed in `scripts/build.sh` by forcing pre-generated-tree
  mtime order (`touch` sources older, generated files newer) right after
  rsync, for both the ppc and x86_64 remote build steps.

- **DMG packaging had no code signing or quarantine handling at all**
  (alephone#5). On modern macOS an unsigned, unnotarized app downloaded/moved
  onto a Mac commonly fails with a false "app is damaged, move to trash"
  dialog instead of the milder "unidentified developer" prompt. Added ad-hoc
  codesigning (`codesign --force --deep -s -`) and quarantine stripping
  (`clear-launch-quarantine.sh`, a shared primitive from old-mac-build-host)
  to `package-dmg.sh`. Verified: took `imac-2019` (Sequoia) from launching
  nothing at all to a real running process via LaunchServices `open`. Note:
  `spctl -a -vv` still reports `rejected` there — ad-hoc signing alone does
  not satisfy Sequoia's default Gatekeeper policy without a paid Developer ID
  + notarization, which is out of scope (no Apple developer account, £0
  hosting policy). The realistic remaining gap is a one-time right-click-Open
  workaround, not full elimination of the prompt.

- **`scripts/deploy-dmg.sh`/`smoke-dmg.sh` (new): several remote-shell
  portability bugs found writing them against real fleet OSes.** `set -o
  pipefail` aborts outright with "invalid option name" on Tiger's stock bash
  2.05b, silently leaving `-e`/`-u` unset too since bash applies none of a
  `set` command's flags when one is invalid — dropped it from the remote
  heredocs. `open -g` (background launch) doesn't exist on Tiger/Panther's
  `open` and it mishandles the unrecognized flag by silently dropping the
  real path argument rather than erroring — dropped `-g`. `pgrep` doesn't
  exist pre-Leopard-ish; replaced with a portable `ps -Awww -o command= | grep`
  (`www` to defeat `ps`'s COMMAND-column truncation, which produced a false
  "process not running" against a 23-character path cut down to 10 chars in
  testing). `open`-over-SSH does not launch anything at all on Tiger/Panther
  (control-tested with Apple's own Chess.app: launches fine over SSH on Snow
  Leopard, launches nothing at all — no error, no process — on Tiger), so a
  FAIL from these scripts on a 10.3/10.4 target does not prove a packaging
  bug; only a real console double-click does there. Unconditionally calling
  `osascript -e 'tell application X to quit'` is also unsafe: it launches X
  first if X isn't already running (a classic AppleScript gotcha) and then
  hangs waiting on that launch — gated all quit attempts on the process
  actually being confirmed running first.

- **Game died at launch when SDL2 was built `--disable-joystick`** (alephone#2).
  `shell.cpp` passed `SDL_INIT_JOYSTICK|SDL_INIT_GAMECONTROLLER` in one combined
  `SDL_Init` and called `exit(1)` on any failure; a joystick-less SDL (every
  fleet PPC tree) errors on exactly those flags with video and audio fine.
  Fix: retry `SDL_Init` without the joystick flags on failure and log it —
  gamepads light up iff the SDL2 slice supports them. Mechanism verified
  against a real `--disable-joystick` SDL 2.30.10 build (init fails with
  "SDL not built with joystick support", base retry succeeds).

- **Autotools build on macOS never linked the Cocoa platform files.**
  `csalerts_sdl.cpp`/`cspaths_sdl.cpp` expect `system_alert_user`,
  `get_application_name` etc. from `csalerts.mm`/`cspaths.mm` when SDL defines
  `__MACOSX__`, but `Source_Files/CSeries/Makefile.am` only listed the `.mm`
  files as `EXTRA_` sources, so every Darwin autotools link failed with
  undefined symbols (upstream only builds macOS via Xcode). Fix: new
  `TARGET_DARWIN` automake conditional in `configure.ac` adds them to
  `libcseries_a_SOURCES` on `*-darwin*`. Matters here because the PPC cross
  build goes through autotools, not Xcode.

- **`-Wl,-exported_symbols_list` (alephone#11's Leopard libstdc++-collision
  fix, `4ab82a53`) fixed real Leopard hardware but broke real Tiger hardware
  100% of the time — reverted same day.** Verified the fix itself first, on
  the actual engine binary (not the earlier synthetic repro): real imac-g5
  run, `DYLD_PRINT_BINDINGS`, 188 cross-image `libstdc++.6.dylib` binds down
  to 0, reached hardware OpenGL init, no crash-reporter entry. Then ran the
  identical binary on real mini-g4 (Tiger 10.4.11) as part of the same
  verification pass, since the fat binary's one ppc slice has to run on both
  — 100% reproducible `EXC_BAD_ACCESS`/`KERN_PROTECTION_FAILURE` at process
  *startup*, before any application code runs (crash trace:
  `_malloc_initialize` <- `calloc` <- `dwarf2_unwind_dyld_add_image_hook` <-
  dyld's `imageNotification`/`registerAddCallback` <-
  `__keymgr_dwarf2_register_sections` <- `_start`). Confirmed a real
  regression, not pre-existing: the identical binary minus this one flag ran
  2+ minutes on the same mini-g4 hardware without it (still shows the
  original malloc-corruption warnings this ticket opened with, but doesn't
  hard-crash at launch). Tiger's dyld (46.16, much older than Leopard's)
  apparently needs something in the exported-symbol table that restricting
  it to just `_main` strips, for its DWARF-unwind image-registration
  handshake. Reverted the flag; `scripts/ppc-exported-symbols.txt` is left
  in the tree, just unreferenced, for a follow-up that finds a narrower
  export list safe on both OS versions. Leopard is back to the
  already-documented (not new) locale/libstdc++ collision this ticket is
  still open for.

- **Follow-up, same day: `-Wl,-unexported_symbols_list` deny-list replaces
  the failed allow-list, real-hardware tested on both OSes — real
  improvement, not a fully closed loop.** Buildhost's hypothesis: an
  ALLOW-list (only `_main` exported) hid too much, including whatever
  libgcc.a/runtime-support symbol Tiger's dyld needs for its DWARF-unwind
  registration handshake; a DENY-list naming only libstdc++.a/`__gnu_cxx`/
  `__cxxabiv1` symbols (`scripts/ppc-libstdcxx-unexport-list.txt`, generated
  from our own baseline ppc binary via `nm -m`, ~11.2k symbols) should hide
  the real collision surface without touching libgcc.a. Rebuilt and verified
  on real hardware, not the synthetic repro this time: **imac-g5** (Leopard)
  — 0 of the original-direction `libstdc++.6.dylib:...$lazy_ptr = Aleph
  One:...` binds (down from 188), 45s soak with continuous forward progress
  (real GL shader-compilation activity — `libGLProgrammability.dylib`,
  `glvm*` — not a stuck/spinning process), zero malloc-corruption warnings,
  no new crash-reporter entry. **mini-g4** (Tiger) — two separate runs
  (18s, 45s), no crash, no crash-reporter entry at all (vs. instant SIGBUS
  with the allow-list attempt).
  **Real caveat found that the synthetic repro didn't surface**: the
  deny-list also causes a NEW, opposite-direction cross-image bind class —
  our own code's weak references to symbols we just unexported (stream
  destructors `~istream`/`~ostream`/`~iostream`, `std::string::_Rep`
  sentinel statics, locale facet `id`s for `moneypunct`/`collate`/
  `num_get`/`num_put`/`time_get`/`time_put`/`messages`, `__gnu_cxx` concept-
  check no-ops) now resolve into the SYSTEM's `libstdc++.6.dylib` instead of
  our statically-linked copy — the same ABI-mismatch risk class this whole
  investigation started from, just reversed. ~200 such binds measured on
  imac-g5 in the 45s trace. Did not manifest as a crash or corruption in
  testing performed (including exercising the original crash site —
  `ScenarioChooser::add_directory`'s ifstream construct/destruct, which
  happens early in this same run), but this is real residual risk, not a
  clean zero, and wasn't caught by buildhost's minimal synthetic test
  because it didn't exercise real iostream/string/locale-facet code the way
  the actual engine does. Recorded on alephone#11 rather than silently
  accepted as fully fixed.

- **`scripts/deploy-dmg.sh` aborted the whole deploy on `yosemite` (Panther
  10.3.9) — apps got copied but never quarantine-cleared.** `hdiutil detach
  <mountpoint-path>` fails outright on this box ("detach failed - No such
  file or directory"), every time, any path form tried; detaching the same
  mount by device node works first try (real Panther `hdiutil` quirk,
  diagnosed and reproduced by buildhost with `bash -x`, not guessed). Under
  `set -eu` that failure aborted the script right at the unguarded `hdiutil
  detach` call, before the quarantine-clear loop that ran after it ever got
  a chance — apps sitting un-quarantine-cleared on a machine someone's about
  to double-click is worse than a DMG staying mounted. Fix: reordered so
  quarantine-clear runs before detach, and detach now looks up the device
  node from `mount`'s own output first (falling back to the path form),
  with either attempt logging a warning instead of aborting the script.

- **arm64 slice (alephone#17): `configure.ac` unconditionally linked
  `-framework AGL` for any Darwin target, and AGL.framework is gone entirely
  from Xcode 26's SDK.** Building the new native arm64 slice failed at link
  time: `ld: framework 'AGL' not found`. AGL is Carbon-era and nothing in
  this codebase actually calls into it any more — the handful of "AGL" hits
  under `Source_Files/` are historic changelog comments, not live code; SDL2
  owns GL context creation and buffer swap. Fixed by probing for it with a
  real `AC_LINK_IFELSE` check instead of assuming it, so the older PPC/Intel
  SDKs that still ship AGL keep linking it exactly as before, and only a
  sysroot that genuinely lacks it (arm64's, so far) drops it.

- **arm64 slice: openal-soft 1.25.2's own build enables
  `-Werror=function-effects` on clang ≥ 20, and Xcode 26/clang 21's
  `CoreAudioTypes.framework` header trips it on `coreaudio.cpp`'s
  `inputProc` lambdas** ("attribute 'nonblocking' should not be added via
  type conversion") — a real upstream/SDK version mismatch, not a behavior
  change; removing the lambdas' `noexcept` didn't help, since the diagnostic
  turned out to be about the target C function-pointer type, not the source
  lambda. Fixed at the dependency's own build config (forcing
  `HAVE_WFUNCTION_EFFECTS` off in its `CMakeLists.txt`), not by patching
  engine code.

- **imac-2019 as an x86_64 build host (alephone#15): the shared GCC 7.5
  bootstrap cross-toolchain doesn't run on Sequoia at all.** It exists to
  build the PPC cross-compiler on Lion, not to compile application code, and
  its own bundled `ld` can't find `libSystem` on a modern host: `ld:
  library 'System' not found`. `build.sh`'s x86_64 branch now probes for a
  working link with that toolchain at runtime rather than assuming it works
  everywhere, and falls back to native clang + Homebrew where it doesn't —
  imac-2019 is genuinely x86_64, so cross-compiling through an old bootstrap
  compiler there was never necessary. That fallback path's deployment-target
  floor is 10.9, not the GCC 7.5 path's 10.6: asio needs `__thread`-based
  TLS, unsupported by the Mach-O ABI below 10.7, measured directly (a bare
  `#include <asio.hpp>` fails to compile at `-mmacosx-version-min=10.6`,
  "thread-local storage is not supported for the current target").
