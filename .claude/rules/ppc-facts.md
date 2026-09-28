---
paths:
  - "scripts/build*.sh"
  - "scripts/*deps*.sh"
  - "scripts/check-ppc-symbols.sh"
  - "PORTING-PPC.md"
  - "BUILD-HOST.md"
---

# PPC build facts

- **SDL2 floor is 2.0.3.** AO calls no newer API (`SDL_SoftStretchLinear` falls back to `SDL_BlitScaled`); no SDL2 fork needed.
- **Six deps**, all else `--without-*`: SDL2, SDL2_ttf, boost **1.76.0** (not 1.90: boostorg/atomic#79), asio, libsndfile, **openal-soft 1.23.1** (not 1.24+: broken big-endian AltiVec). Apple's `OpenAL.framework` lacks `ALC_SOFT_loopback` and EFX, so it cannot substitute.
- **GCC 14, pinned.** GCC 15 broke on Tiger PPC (PR 123976); GCC 16 dropped flags the bootstrap needs; clang has no PPC backend.
- **Weak-linking is the governing risk:** one 10.4-only symbol links fine, then dyld aborts on a 10.3.9 G3. Run `nm -arch ppc -u` against the 10.3.9 symbol set for every linked binary (`scripts/check-ppc-symbols.sh`).
- **Runtime feature detection, not per-machine tuning:** one ppc slice at the lowest deployment target; GL 2.0, IOHIDManager and gamepads light up by runtime check.
- **The same fat binary shipped as AO 1.0-1.2.1** (2011-2015, `8042f4f2`, tag `release-20150620`); SDL2 alone ended it, not endianness.
- Crash and link lessons (libstdc++ collision, `std::locale`): `docs/ppc-lessons.md`.
