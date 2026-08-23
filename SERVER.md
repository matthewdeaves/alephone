# Dedicated server — findings, 2026-08-23

Investigated for the manager after a peer session raised: "check whether this
engine can run a dedicated server at all before assuming it maps onto the
other four ports." Answer: it already can. There is a real, headless,
already-shipping dedicated server in this codebase, `standalone_hub`. The
premise that nothing like it exists here is wrong.

## What exists — measured from source, not reasoned

- `Source_Files/Network/StandaloneHub/` is a second `main()` and a separate
  build target, not a flag on the normal game client.
  `configure.ac:76-82` wires `--enable-standalone-hub` to
  `AM_CONDITIONAL([STANDALONE_HUB])` and `#define A1_NETWORK_STANDALONE_HUB`.
  `Source_Files/Makefile.am:6-9`: when that's set, `bin_PROGRAMS =
  standalone_hub` **instead of** `alephone` — mutually exclusive targets from
  the same tree.
- **Genuinely headless, not "video off".** `standalone_hub_main.cpp:main()`
  calls `initialize_hub()` → `initialize_marathon()`
  (`Source_Files/GameWorld/marathon2.cpp:155`). It never calls
  `initialize_application()` (`shell.cpp:228`), which is the *only* place
  `SDL_Init(SDL_INIT_VIDEO|...)` is called (`shell.cpp:236`). SDL video is
  never touched — no dummy driver needed, because nothing asks for one.
- **Already packaged and released, upstream.** `Dockerfile.hub`: Alpine,
  `--enable-standalone-hub --disable-opengl`. `.github/workflows/
  release-standalone-hub.yml`: builds that image, pushes
  `ghcr.io/<owner>/standalone-hub:<ver>` on `workflow_dispatch`/
  `workflow_call`. Checked upstream's own run history for this exact
  workflow: `gh run list -R Aleph-One-Marathon/alephone
  --workflow=release-standalone-hub.yml` — last two runs `ok`. It currently
  builds and ships on upstream's CI. **Not yet run in this fork** — this
  fork's Actions have never fired at all (0 registered workflows, separate
  finding, unrelated to this feature).
- Authored 2024, "Benoit Hauquier and the Aleph One developers" — mainline
  upstream code inherited by the fork, not something added here.

## What it actually is — the peer's caution was partly right

Not an idTech-style dedicated server that runs a whole match standalone from
a config file with zero human involvement, ever. AO's model is genuinely
different — confirmed by reading `standalone_hub_main.cpp` in full:

- One human player is still the **gatherer**: `StandaloneHub::
  WaitForGatherer()`, `GetGameDataFromGatherer()`. The gatherer supplies the
  map WAD, physics and topology, then either disconnects or stays on as a
  normal client (`GathererJoinedAsClient()`).
- Once gathering completes, the hub itself drives `NetStart()`,
  `NetChangeMap()`, `NetSync()`, and per-tick `NetProcessMessagesInGame()` —
  the same network state-machine calls a real client makes. It is the
  authoritative star-topology host for the whole match, headless, not a
  rendezvous point that hands off to a peer.
- Matches AO's known networking history: an original peer-hosted "ring"
  topology, later a "star" topology with a hub role. `Source_Files/Network/
  network_star.h` and `network_star_hub.cpp` implement the wire protocol;
  `StandaloneHub` is the headless embodiment of the hub side of it.

## Answering the three questions asked

1. **Can it host without a display, no human playing?** Yes, for the
   duration of a match — measured from source, above. A human must still
   gather once per game/map cycle to supply the ruleset; whether that step
   can itself be scripted with no human ever involved is **not confirmed**,
   needs a runtime test, not just a source read.
2. **Minimum viable version?** Already exists and already builds — no
   null-video-driver workaround needed, because video is never initialized
   in this binary.
3. **Prior art?** This binary IS the prior art — already mainline, not
   something to go looking for in the issue tracker. Searched upstream
   issues for "hub" / "standalone hub" anyway: nothing further turned up.

## Left to do — all unmeasured by me so far

1. Build `standalone_hub` in **this fork** and confirm it actually runs —
   untested here specifically; this fork's CI has never fired at all.
2. Confirm a real PPC/Intel client can complete a gather against a
   Linux-hosted `standalone_hub` — cross-arch/cross-endian wire compat is
   unverified in either direction.
3. Hosting/deployment is `retro-server-infra`'s call, not this repo's — this
   repo ships the binary/image, sequencing across repos is the manager's.
