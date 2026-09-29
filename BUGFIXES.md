# Bugfixes

Search by ticket or date; entries are newest first.
Archive: `docs/archive/BUGFIXES.md`.
Dates added to undated accounts identify their recorded evidence or first Git record, not a newly inferred incident date.

## alephone#47 Radeon 9700 (R300): shader renderer 0.1 fps, now auto-picks classic GL
Symptom: 0.1 fps on qemu-tiger3d (G4 + Radeon 9700 PRO, Tiger; qemu#10). sprite/wall.frag branch per-pixel; R300 -> CPU (PPEmulatorRun).
Fix: screen.cpp known_bad_shader_gpu GL_RENDERER match (alephone#16) adds "Radeon 9700". package-dmg.sh: guard `cat` of absent lipo log.
Verified qemu-tiger3d, no override: gl-tier 0 picked, 30.3/60.3/139.1 fps; check-ppc-symbols.sh PASS (530 strong, 0 weak).
Real imac-g5 (Leopard 10.5.8, reports "Radeon 9600"): classic picked unforced, 30.3/59.9/59.8 fps, no regression.
Caveat: the literal "Radeon 9700" match is VM-evidence-only; no real 9700/9800/X300-X600 card was available.

## alephone#45 bench-evidence.sh read INVALID on slow real hosts despite a live, verified run
Symptom: "liveness did not advance" / "frames byte-identical" on imac-g5 while fps-log showed continuous gameplay.
Cause: bench-adapter.sh bench_launch quit the game 6s after returning; ssh/hash/capture/ping overhead ate 3-8s on Leopard PPC.
Fix: hardcoded 6s replaced by tunable ALEPHONE_BENCH_QUIT_GRACE, default 20s. Confirmed with a 30s direct unwrapped run.

## alephone#39 Intel GMA 950 Macs ran at about 1 fps by default (also alephone#30)
Cause: GPU advertises GLSL so shader renderer was chosen, but it has no hardware vertex shaders (GL 1.4).
mini-intel (Lion, 800x600, uncapped, x86_64+i386): shader 0.6-1.8 fps (0.9-1.8 s frames), classic 6.8-6.9 fps (~150 ms).
Fix: added "GMA 950" to the classic-GL GPU list beside "Radeon 9600"; covers every Core Solo/Duo Mac the i386 slice targets.

## alephone#39 Film/file passed on command line hung macOS startup before the window opened
Symptom: app frontmost, menu bar only, ignored Quit; blocked fps benches. sample: main thread in SDL_Init, modal alert never drew.
Cause: SDL Cocoa_RegisterApp calls [NSApp finishLaunching] before its delegate exists; argv taken as documents, NSDocumentClass empty.
Fix: NSTreatUnknownArgumentsAsOpen=NO before SDL_Init (system_disable_argv_document_open, csalerts_darwin.cpp), plain objc-runtime C.
A/B imac-2019: v1.1.0 stuck in runModal, 0 fps; fixed build replayed the film at 114 fps, tier 2.

## alephone#34 Release candidate could not launch on modern macOS when fat binary had a ppc slice
Found in imac-2019 (Sequoia) smoke check. Cause: package-dmg.sh shipped bundle fully unsigned if ppc present; RunningBoard refuses (code 5).
Isolation: a signed, ppc-stripped copy of the same binary launched fine.
Fix: thin out ppc, ad-hoc codesign the rest, lipo the untouched ppc slice back (sha256-identical before/after).
Verified real deploy + LaunchServices launch on imac-2019 (SMOKE PASS, alive 10s+).
Caveat: not verified on real arm64 hardware.

## alephone#16 PPC/Leopard ATI R300: shader renderer ~0.5 fps despite full GLSL reported
Real imac-g5 (Radeon 9600/RV351) unplayable; mini-g4 (older GPU, classic renderer) "played lovely". Two causes:
1) Shader floor/ceiling + viewer sprite used GL_POLYGON (28% in gleFallbackBegin); GL_TRIANGLE_FAN/GL_QUADS (675a0ea6), small gain.
2) Sprite GLSL (Shader::S_Sprite) ran in driver software interpreter (gldLLVMFPTransformFallback, glvmInterpretFPTransformFour).
Fix: screen.cpp GL_RENDERER "Radeon 9600" forces classic Rasterizer_OGL_Class/OGL_Render.cpp; ALEPHONE_FORCE_CLASSIC_GL=1 overrides.
Verified real imac-g5: no fallback hits in sample, playtest "totally playable". Other R300 parts (9500-9800, X300-X800) unconfirmed.

## alephone#11 PPC/Leopard: two 100%-reproducible SIGILL crashes on every launch (from alephone#5)
Real imac-g5 (10.5.8), crash-reporter Binary Images; both fixed, verified by 15s+ direct runs.
1) boost iptree less_nocase std::toupper(ch, locale): GCC14 PPC miscompiles. scripts/patches/boost-1.76.0-less_nocase-no-locale.patch.
2) istream>>(short&) via stream_translator: system libstdc++.6.dylib (via AudioToolbox etc.) wins. Fix: -Wl,-force_load libstdc++.a/libgcc.a
Then unresolved: `malloc: *** error ... Non-aligned pointer being freed` (also Marathon 1); suspect PPC struct-alignment/big-endian bug.
Follow-up: the -unexported_symbols_list entry (also alephone#11) below.

## alephone#5 x86_64 slice: `dyld: Library not loaded` on every machine but the build host
Found on imac-2019 (Sequoia). Cause: linked libSDL2-2.0.0.dylib by absolute path /Users/mini/oldmac/sdl2-x86_64/lib/...; other deps static.
Fix: build.sh fetches the .dylib and retargets its load command to @executable_path on the THIN slice before lipo.
Must precede lipo: current install_name_tool fails on the ppc slice ("malformed load command 0 (cmdsize is zero)").
package-dmg.sh bundles the dylib into Contents/Frameworks/ (same shape as quakespasm's SDL.framework).

## alephone#9 package-dmg.sh version string collided between client and server tags
Symptom: with server-v1.0.0 on the same commit, client DMG was named Marathon-OldMac-server-v1.0.0.dmg.
Cause: `git describe --tags --always --dirty` picks nearest tag regardless of namespace.
Fix: restrict each script's `git describe --match` to its namespace (release-*/v[0-9]* client, server-v* server).

## alephone#9 First server-v1.0.0 shipped with no systemd unit and a fabricated CLI usage doc
Caught by retro-server-infra pre-deploy. README.txt -p/-n/-m/-g never existed; real usage (standalone_hub_main.cpp) is one positional port.
Fix: added systemd/alephone-server.service, deliberately without console-FIFO-on-fd-3 (standalone_hub never reads stdin).
Caveat: not self-hosting; a real client must still complete a GUI-only "gatherer" handshake before a match, unscripted.

## alephone#5 DMGs could not mount on real 10.3.9 Panther (also alephone#7)
Error: `hdiutil: attach failed - no mountable file systems`. Cause: `hdiutil create` defaults to GPT (2006, Intel Macs); Tiger+ reads it.
Fix: `hdiutil create ... -layout SPUD` (Apple Partition Map).
Verified on real 10.3.9 before (fails) and after (mounts); Tiger and later still mount it.

## alephone#6 Every DMG was software-renderer-only on every architecture
Cause: scripts/build.sh hardcoded --disable-opengl for both the ppc and x86_64 configure runs (not PPC-only).
Fix: drop the flag, let configure auto-detect.

## alephone#6 PPC cross-compile with OpenGL on pulled dispatch/dispatch.h (absent pre-10.6)
Cause: configure.ac Darwin OpenGL block hardcodes -F/System/Library/Frameworks, shadowing the 10.3.9 SDK with host CoreFoundation.
Fix: removed the explicit path; plain -isysroot (already set) resolves SDK frameworks (verified empirically).

## alephone#6 PPC link with OpenGL: GL_EXT_framebuffer_object, GL2 status symbols not in 10.3.9 stub
Fix 1: OGL_Shader.cpp mixed ARB and core-GL2 calls; now glGetObjectParameterivARB/glGetInfoLogARB/glDeleteObjectARB (mixing is UB anyway).
Fix 2: OGL_FBO.cpp EXT_framebuffer_object has no ARB fallback; resolved via SDL_GL_GetProcAddress with a safe no-op fallback.
Also closes a latent crash: Rasterizer_Shader.cpp constructs FBOSwapper unconditionally with no capability check.

## alephone#6 PPC cross-build sometimes regenerated aclocal.m4/configure with absent aclocal-1.18
Cause: rsync loses autotools dependency-order mtimes; without AM_MAINTAINER_MODE the regen rules are always live.
Fix: scripts/build.sh touches sources older and generated files newer right after rsync, for ppc and x86_64.

## alephone#5 DMG packaging had no code signing or quarantine handling
Symptom: unsigned app on modern macOS commonly shows false "app is damaged, move to trash".
Fix: package-dmg.sh adds ad-hoc `codesign --force --deep -s -` + quarantine stripping (clear-launch-quarantine.sh, old-mac-build-host).
Verified: imac-2019 (Sequoia) went from launching nothing to a running process via LaunchServices `open`.
Caveat: `spctl -a -vv` still says rejected (no Developer ID/notarization, out of scope); one-time right-click-Open remains.

## 2026-09-28 (no ticket) deploy-dmg.sh/smoke-dmg.sh remote-shell portability bugs on real fleet OSes
`set -o pipefail` errors on Tiger bash 2.05b and leaves -e/-u unset: dropped. `open -g` on Tiger/Panther drops the path arg: dropped.
`pgrep` absent pre-Leopard: use `ps -Awww -o command= | grep` (www avoids COMMAND truncation and false "not running").
Bare `osascript ... to quit` launches X then hangs: gate on process confirmed running.
`open` over SSH launches nothing on Tiger/Panther (Chess.app control): FAIL there is no proof of a packaging bug; use console double-click.

## alephone#2 Game died at launch when SDL2 was built --disable-joystick
Cause: shell.cpp passed SDL_INIT_JOYSTICK|SDL_INIT_GAMECONTROLLER in one SDL_Init, exit(1) on failure (fleet PPC SDL trees lack joystick).
Fix: retry SDL_Init without joystick flags and log it; gamepads work iff the SDL2 slice supports them.
Verified against a real --disable-joystick SDL 2.30.10 ("SDL not built with joystick support", retry succeeds).

## 2026-09-28 (no ticket) Autotools build on macOS never linked the Cocoa platform files
Cause: csalerts_sdl.cpp/cspaths_sdl.cpp need csalerts.mm/cspaths.mm symbols; Makefile.am listed them only as EXTRA_; Darwin links failed.
Fix: new TARGET_DARWIN automake conditional in configure.ac adds them to libcseries_a_SOURCES on *-darwin*.
Matters because the PPC cross build uses autotools, not Xcode (upstream builds macOS only via Xcode).

## alephone#11 Leopard libstdc++ collision: -unexported_symbols_list deny-list replaced allow-list
Superseded first try -Wl,-exported_symbols_list (4ab82a53; fixed Leopard, crashed Tiger at startup): docs/archive/BUGFIXES-superseded.md.
Final fix: deny-list of libstdc++.a/__gnu_cxx/__cxxabiv1 symbols, scripts/ppc-libstdcxx-unexport-list.txt (~11.2k, `nm -m`); libgcc.a kept.
Real hw: imac-g5 (Leopard) 0 libstdc++.6.dylib cross-image binds (was 188), 45s soak, no malloc warnings; mini-g4 (Tiger) 18s/45s, no crash.
Residual risk: ~200 reverse binds (~istream/~ostream, string _Rep, locale facet ids) now hit SYSTEM libstdc++; no crash seen.
Synthetic repro missed this; recorded on alephone#11, not called fully fixed.

## 2026-09-28 (no ticket) deploy-dmg.sh aborted on yosemite (Panther 10.3.9) before quarantine-clear
Cause: `hdiutil detach <mountpoint-path>` always fails there ("No such file or directory"); by device node works. `set -eu` aborted.
Diagnosed by buildhost with `bash -x`. Effect: apps copied but never quarantine-cleared.
Fix: quarantine-clear now runs before detach; detach uses device node from `mount` first, falls back to path, warns instead of aborting.

## alephone#17 arm64 slice: configure.ac linked -framework AGL, gone from Xcode 26 SDK
Error: `ld: framework 'AGL' not found`. AGL is unused Carbon-era (remaining Source_Files hits are changelog comments); SDL2 owns GL context.
Fix: probe with a real AC_LINK_IFELSE check; older PPC/Intel SDKs still link AGL, only sysroots lacking it (arm64) drop it.

## 2026-09-28 (no ticket) arm64 slice: openal-soft 1.25.2 -Werror=function-effects vs Xcode 26 CoreAudioTypes
Cause: openal-soft enables it on clang >= 20; clang 21 header trips coreaudio.cpp inputProc lambdas ("'nonblocking' ... type conversion").
Removing the lambdas' noexcept did not help (diagnostic concerns the target C function-pointer type).
Fix: forced HAVE_WFUNCTION_EFFECTS off in the dependency's CMakeLists.txt, not engine code.

## alephone#15 imac-2019 as x86_64 build host: shared GCC 7.5 bootstrap toolchain fails on Sequoia
Error: bundled ld `ld: library 'System' not found` (toolchain exists to build the PPC cross-compiler on Lion, not app code).
Fix: build.sh x86_64 branch probes for a working link at runtime, else native clang + Homebrew.
Fallback deployment-target floor is 10.9 (GCC path 10.6): asio needs __thread TLS, fails at -mmacosx-version-min=10.6.

## 2026-09-28 (no ticket) G3 (yosemite, 10.3.9): SDL_OpenFPFromBundleOrFallback called NSAutoreleasePool drain
Crash: EXC_BREAKPOINT in _NSRaiseError via _objc_msgForward (unrecognized selector); ScenarioChooser::add_scenario -> SDL_RWFromFile.
Cause: -drain is 10.4+ (Panther Foundation 6.3.6 lacks it). Bug was in panther-sdl2 (fleet SDL 2.0.3 fork), not alephone source.
Fix: swapped to -release there (same without ObjC GC); ppc slice's SDL2 rebuilt.
Verified on the same real G3: reaches scenario chooser and plays, no new crash report.

## alephone#24 EXC_BREAKPOINT in NSWindow setContentSize/Cocoa_SetWindowFullscreen, mini-g4 Tiger
2026-09-03. Cause: shell.cpp SDL_WINDOWEVENT_FOCUS_GAINED "Mojave" workaround toggled SDL_SetWindowFullscreen off/on on all Apple builds.
Traps in -[NSWindow _setFrameCommon:display:stashSize:] on Tiger AppKit (not GCC14); scmode_fullscreen="false" predated it.
Fix: gate on sysctlbyname("kern.osrelease") Darwin major >= 18 (Mojave+).
Verified real mini-g4: ppc slice lipo'd into deployed fat binary, --nogl + scenario dir alive 25s+ (crashed ~1s before), clean SIGTERM.

## alephone#21 App Translocation on fresh DMG download: "Map, Shapes, Images, Sounds ... (error -1)"
2026-09-02, imac-2019. Cause: app kept com.apple.quarantine, so macOS ran a read-only AppTranslocation/<uuid>/d/ copy apart from data files.
get_data_path(kPathDefaultData) in cspaths_darwin.cpp uses CFBundleCopyBundleURL(), which breaks there.
Fix, package-dmg.sh, 3 passes: db8549f0 hidden dotfile sidecar (lost on drag), b2fe710f inlined clear+lsregister -f, 94d9dc20 in app dir.
Shipped release-20260902-fat-5; deployed + smoke-tested on imac-2019 (quarantine cleared, launched).
Open: app needed two launch attempts after the fix script; not root-caused.
