# Incidents

Search by ticket or date; entries are newest first.
Archive: `docs/archive/`.

## 2026-09-23 mini-intel2: a smoke's `open -n` hung for 3.5 hours
Shared `smoke-dmg.sh` launched via LaunchServices at 14:39; `open -n` never returned and held my install loop until 18:07.
The claim had vanished, so quakespasm claimed the host at 18:09 with the stuck process still there; I killed it at about 18:12.
Reported to buildhost: bound the 10.6+ `open`, like the pre-10.6 OPEN_CHECK.
Rule: give a background install loop a progress check, not just a completion wait.

## 2026-09-23 g5-panther: install and smoke ran without the host claim
`pick-bench-host.sh --acquire ... | tail -1 || exit 1` tests `tail`'s status, not the picker's; the host was busy and the failure went unread.
Deploy and a 20 s smoke ran alongside another port's claim (about 09:10 to 09:12 BST). Reported to buildhost.
Rule: never pipe `--acquire`; test it directly (`if scripts/pick-bench-host.sh --acquire ...; then`).

## 2026-09-23 mini-g4: bench left two games running into quake2's claim
`bench-fps.sh` killed the subshell wrapping the game, not the game, so each run's process survived.
Fixed with `exec` in 97e3da62.
