# Bug fixes

One short entry per real bug fixed in this fork: what it was, what the fix was.
Newest first.

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
