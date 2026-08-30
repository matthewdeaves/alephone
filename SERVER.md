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

## Update 2026-08-23 — item 1 confirmed, item 2 hits a real limit

**Built `standalone_hub` in this fork, on the workstation, from
`Dockerfile.hub` unmodified:** `docker build -f Dockerfile.hub .` — succeeds
clean, full autotools build inside the Alpine builder stage, no patches
needed. **Ran it:** `docker run ... alephone-standalone-hub-test 15000`, gave
it 15s, still up, `ps aux` inside the container shows `PID 1
./standalone_hub 15000` alive, no crash through the whole
`initialize_hub()`/`initialize_marathon()`/`mytm_initialize()` init chain.
`netstat -tulnp` inside the container: listening on both `tcp` and `udp`
`0.0.0.0:15000`. First time this has been built or run in this fork
specifically — genuinely measured, not just "upstream's CI says so."

**Item 2 (a real gather) is not a quick smoke test — flagging the actual
limit rather than forcing it.** The client side of a gather is GUI-only:
`network_dialogs.cpp:2708-2711`'s "Use Dedicated Server" toggle lives in the
network setup dialog, and there is no CLI or scripted path into it —
`shell_options.cpp`'s flag table (`-f/-w/-g/-s/-m/-j/-Q/-e/--no-chooser`) has
nothing for headless networking. The normal client's `initialize_application()`
(`shell.cpp:228`) always calls `SDL_Init(SDL_INIT_VIDEO|...)` unconditionally
— unlike `standalone_hub`, it cannot skip video, and there's no
`SDL_VIDEODRIVER` override in the engine even if there were a way to drive
the dialog blind. Completing a gather needs either a human at a real display
clicking through that dialog, or a GUI-automation/event-injection harness
that does not currently exist anywhere in this codebase. Not attempting to
build that harness now — out of scope for a smoke test, would need its own
ticket if wanted.

## Left to do

1. ~~Build `standalone_hub` in this fork and confirm it runs~~ **Done,
   measured, above.**
2. ~~A real gather end to end~~ **Done, 2026-08-30, real hardware.** Needed
   a client-side feature first: the game-setup dialog had no way to gather
   through anything but the official metaserver's public hub list, so a
   private `standalone_hub` (this one) was unreachable as a host target.
   Added a "Use Custom Server Address" option (alephone#20). First real
   attempt crashed on `Play`/start-game (null `gMetaserverClient` — the
   "advertise on metaserver" flag gets force-enabled by the host UI for any
   remote-hub game, but the private-hub path deliberately never logs into
   the metaserver to go with it); fixed, then verified clean.
3. ~~Confirm a real PPC/Intel client can complete a gather against a
   Linux-hosted `standalone_hub`~~ **Done, 2026-08-30.** Gathered on a real
   PowerPC Mac (`imac-g5`), joined from a real Intel Mac, and the reverse —
   both directions, real gameplay, against `g.matthewdeaves.com`.
4. Hosting/deployment is `retro-server-infra`'s call, not this repo's — this
   repo ships the binary/image, sequencing across repos is the manager's.
   Its ask (relayed 2026-08-23): a native Linux binary built the same way the
   other four ports release theirs, not the Docker image — matches its
   existing bare-systemd deploy pattern. Already how `server-v1.0.0` ships.
