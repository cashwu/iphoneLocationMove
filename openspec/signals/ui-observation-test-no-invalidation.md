---
id: ui-observation-test-no-invalidation
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/fix-stale-simulation-controls/reviews/propose-r1.md
---
# UI observation regression test 未驗證 view invalidation

修正 reactive UI stale state 時，測試必須觀察同一 rendered hierarchy 在 publisher 更新後切換輸出；只讀 shared reference 的最新 property 不能證明 observation wrapper 觸發 view 重算，可能讓原 regression 在測試全綠時持續存在。

## Occurrences

- 2026-07-27 — `fix-stale-simulation-controls` — `cash-propose` Round 1：原測試只驗證 shared `DeviceSetupStore.simulationStore` 變為非 `nil`，即使缺少 `@ObservedObject` 也會通過。
