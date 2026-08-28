# Bug fixes

One short entry per real bug fixed in this fork: what it was, what the fix was.
Newest first.

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
