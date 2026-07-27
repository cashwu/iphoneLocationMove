---
id: design-mechanism-statement-conflict
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-mac-recenter-and-workspace-reset/reviews/propose-r1.md
---
# Design 內同一機制的敘述互斥

design 對同一機制（對話框、state 擁有者、去重機制等）在 Decisions 與 Implementation Contract 間、或同一條 decision 前後，不得存在互斥敘述（例如同時宣稱「沿用既有 private 機制」與「由另一層自有 state 驅動」）；機制歸屬必須單一且可實作。

## Occurrences

- 2026-07-27 — `add-mac-recenter-and-workspace-reset` — `cash-propose` Round 1：reset 確認對話框同時被寫成「沿用 `SimulationControls` private 的 `PendingMutation`」與「由 `LocationMapView` 自有 state 驅動、不共用」。
