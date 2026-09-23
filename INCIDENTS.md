# Incidents

Things that went wrong on shared fleet machines, and what changed. Newest first.

- **2026-09-23, mini-intel2: a smoke's `open -n` hung for 3.5 hours.** The shared
  `smoke-dmg.sh` ran its 10.6+ LaunchServices launch at 14:39, and `open -n`
  never returned: no game, no verdict. It held my fleet install loop until
  18:07. The claim had vanished while it ran, so quakespasm claimed the host
  at 18:09 with the stuck process still there. I killed it at about 18:12 and
  told quakespasm. Reported to buildhost: bound the 10.6+ `open`, like the
  pre-10.6 OPEN_CHECK. Rule: a background install loop gets a progress check,
  not just a completion wait.
- **2026-09-23, g5-panther: install and smoke ran without the host claim.**
  `pick-bench-host.sh --acquire ... | tail -1 || exit 1` tests `tail`'s exit
  status, not the picker's. The host was busy, and the failure message went
  by unread. The deploy and a 20 s smoke then ran alongside another port's
  claim (about 09:10 to 09:12 BST). Reported to buildhost. Rule: never pipe
  `--acquire`. Test it directly (`if scripts/pick-bench-host.sh --acquire ...; then`).
- **2026-09-23, mini-g4: bench left two games running into quake2's claim.**
  `bench-fps.sh` killed the subshell wrapping the game, not the game, so
  each run's process survived. Fixed with `exec` in 97e3da62.
