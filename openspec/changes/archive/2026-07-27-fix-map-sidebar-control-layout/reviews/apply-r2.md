# Cash Apply Review — Round 2

## Reviewer Findings

### Critical

無。

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`disposition`: fix-introduced；`introduced_by`: Round 1 Fix Actions 新增的 paused transition／probe 驗證；`location`: `iPhoneLocationMoveTests/ContentViewTests.swift` 的 paused transition 與 `waitForRoutePhase`；`summary`: helper 只等待 model state，不能保證同一 hosting hierarchy 已 materialize `sidebar-button-resume-route`，targeted test 曾先失敗再通過，paused probe 驗收具有同步 flake；`recommendation`: 以有 timeout 的 view-condition 同時等待 `.paused` phase 與目標 `TestingLayoutRegionView` 出現，再執行完整 layout oracle；reviewer source: Reviewer V — Verification。

### Suggestion

無。

## Rating

- post-filter cumulative blocking Critical count: 0
- post-filter cumulative blocking Warning count: 1
- non-blocking triaged finding count: 0
- `critical_gap`: false
- `round_type`: micro

Reviewer V 判定 Round 1 cumulative member 仍為 unresolved：baseline 與 route phase 覆蓋本身已補上，但 paused probe 的 UI materialization 等待不 deterministic。此 defect 直接來自 Round 1 Fix Actions，故 disposition 為 `fix-introduced`，累積阻塞集合仍保留一項 Warning。修正已完成，但需下一輪 fresh reviewer 驗證後才能移除，因此本輪為 `next_round`。

## Fix Actions

- 修改 `iPhoneLocationMoveTests/ContentViewTests.swift`：`waitForRoutePhase` 改為最多等待 1 秒，反覆刷新 hosting window，並同時要求 model phase 與指定 layout region identifier 成立；paused oracle 只有在 `sidebar-button-resume-route` materialize 後才執行，timeout 會明確失敗。
- 修改 `openspec/changes/fix-map-sidebar-control-layout/design.md` 與 `tasks.md`：同步記錄 route paused 必須以有 timeout 的條件等待 model phase 與 resume probe materialize。
- Post-fix stability validation：以 `-test-iterations 5` 連續執行 `testConnectedSidebarRelayoutsObservedSimulationStates`，5/5 全部通過。
- Post-fix validation：`cash validate fix-map-sidebar-control-layout` 與 `git diff --check` 通過；identifier cross-grep 確認 `waitForRoutePhase`、`sidebar-button-resume-route` 與 timeout contract 一致。

## Decision

next_round
