---
id: mutation-terminal-state-type-split
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/recover-dropped-device-tunnel/reviews/propose-r2.md
  - openspec/changes/recover-dropped-device-tunnel/reviews/propose-r5.md
---
# Mutation terminal state 未依操作類型分流

外部mutation共用recovery機制時，terminal state仍須依操作語意分流；active `set` failure可進入position-unknown interruption，但`clear` failure必須保留cleanup ownership與retry，不得被總括failure wording帶回idle或另一個互斥state。

## Occurrences

- 2026-07-27 — `recover-dropped-device-tunnel` — `cash-propose` Rounds 2、5：clear-specific cleanup contract最初缺少直接測試，後續總括文字仍與`set` failure共用`interrupted(positionUnknown)`。
