# Incidents

Things that went wrong on shared fleet machines, and what changed. Newest first.

- **2026-09-23, g5-panther: install and smoke ran without the host claim.**
  `pick-bench-host.sh --acquire ... | tail -1 || exit 1` tests `tail`'s exit
  status, not the picker's. The host was busy, and the failure message went
  by unread. The deploy and a 20 s smoke then ran alongside another port's
  claim (about 09:10 to 09:12 BST). Reported to buildhost. Rule: never pipe
  `--acquire`. Test it directly (`if scripts/pick-bench-host.sh --acquire ...; then`).
- **2026-09-23, mini-g4: bench left two games running into quake2's claim.**
  `bench-fps.sh` killed the subshell wrapping the game, not the game, so
  each run's process survived. Fixed with `exec` in 97e3da62.
