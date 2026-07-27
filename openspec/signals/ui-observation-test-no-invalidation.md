---
id: ui-observation-test-no-invalidation
type: recurring-finding
status: open
occurrences: 3
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/fix-stale-simulation-controls/reviews/propose-r1.md
  - openspec/changes/fix-map-sidebar-control-layout/reviews/propose-r1.md
  - openspec/changes/fix-map-sidebar-control-layout/reviews/apply-r2.md
---
# UI observation regression test 未驗證 view invalidation

修正 reactive UI stale state 時，測試必須觀察同一 rendered hierarchy 在 publisher 更新後切換輸出；只讀 shared reference 的最新 property 不能證明 observation wrapper 觸發 view 重算，可能讓原 regression 在測試全綠時持續存在。

## Occurrences

- 2026-07-27 — `fix-stale-simulation-controls` — `cash-propose` Round 1：原測試只驗證 shared `DeviceSetupStore.simulationStore` 變為非 `nil`，即使缺少 `@ObservedObject` 也會通過。
- 2026-07-27 — `fix-map-sidebar-control-layout` — `cash-propose` Round 1：原布局測試規劃為每種 state 重建 fixture，無法證明同一 rendered hierarchy 在 `SimulationStore` publisher 更新後重新 layout。
- 2026-07-27 — `fix-map-sidebar-control-layout` — `cash-apply` Round 2：paused 測試只等待 model phase，未等待同一 hosting hierarchy materialize resume probe，造成同步 flake。
