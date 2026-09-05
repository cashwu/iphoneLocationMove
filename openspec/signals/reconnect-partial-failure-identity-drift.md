---
id: reconnect-partial-failure-identity-drift
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-09-05
last_seen: 2026-09-05
links:
  - openspec/changes/auto-reconnect-after-usb-replug/reviews/propose-r1.md
---
# Reconnect 中途失敗留下半套 session 與 stale generation

logical reconnect（新 generation、重建 transport、先 clear 再 ready）在中途階段失敗時，adapter 若保留已建立的新 session／lease 而上層仍持舊 generation，之後每筆 mutation 都會落入 `staleGeneration` 而非可重試的 typed 中斷，且再次 reconnect 會平行建立第二個 lease。design 必須為 reconnect 的每個失敗階段定義收斂狀態：不留半套 session、保留 disconnected 記錄、任何時刻最多一個 lease，使下一次使用者動作仍能完整重跑。

## Occurrences

- 2026-09-05 — `auto-reconnect-after-usb-replug` — `cash-propose` Round 1：`reconnect()` 在 clear 階段失敗後 adapter 持有新 generation 的 `cleanupPending` session，SimulationStore 舊 generation 的 stop／start 會收到 `staleGeneration`，重回本 change 要修的「只能重開 App」死局。
