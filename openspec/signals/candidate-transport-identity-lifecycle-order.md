---
id: candidate-transport-identity-lifecycle-order
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/recover-dropped-device-tunnel/reviews/propose-r3.md
  - openspec/changes/recover-dropped-device-tunnel/reviews/propose-r4.md
---
# Candidate transport identity lifecycle 順序矛盾

replacement transport在commit前必須使用transaction-scoped candidate identity驗證reply；identity只能在其所有組成資源實際取得後建立，candidate reply先形成local result，待ownership重驗證與atomic commit後才能發布logical success。

## Occurrences

- 2026-07-27 — `recover-dropped-device-tunnel` — `cash-propose` Rounds 3、4：candidate replay一度被current-generation gate拒絕，且完整identity被描述為在DVT handle取得前建立。
