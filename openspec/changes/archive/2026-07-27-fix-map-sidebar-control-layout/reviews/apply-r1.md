# Cash Apply Review — Round 1

## Reviewer Findings

### Critical

無。

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `iPhoneLocationMoveTests/ContentViewTests.swift` 的 `testConnectedSidebarRelayoutsObservedSimulationStates()` 與 `assertSidebarLayout(requiredPrimaryButtonIdentifiers:)`；`summary`: connected idle、busy、stopping failure 的 layout oracle 未傳入主要操作 identifier，造成 baseline 驗證實際為空，且測試未進入 route running／paused，因此 pause／resume probe 未被驗證；`recommendation`: 各狀態傳入當下可見的主要按鈕集合，並在同一 rendered hierarchy 驅動 route running／paused 後重跑完整 layout oracle；reviewer source: Reviewer A — Adherence、Reviewer B — Quality。

### Suggestion

無。

## Rating

- post-filter cumulative blocking Critical count: 0
- post-filter cumulative blocking Warning count: 1
- non-blocking triaged finding count: 0
- `critical_gap`: false
- `round_type`: full

兩位 reviewer 的 finding 依相同 location 與 summary 聚合為一項 Warning，且有本次新增測試的直接證據，故保留在 cumulative blocking set。修正已完成，但必須由下一輪 fresh reviewer 驗證後才能移除，因此本輪為 `next_round`。

## Fix Actions

- 修改 `iPhoneLocationMoveTests/ContentViewTests.swift`：connected fixture 在 idle、busy、route running、route paused、stopping failure 五個狀態均傳入當下可見的主要操作 identifier，實際執行 baseline oracle；在同一 hosting hierarchy 啟動路線並切換 pause，驗證 pause／resume／stop probe，等待 route phase 完成後再斷言。
- 修改 `openspec/changes/fix-map-sidebar-control-layout/proposal.md`、`design.md`、`specs/location-simulation/spec.md` 與 `tasks.md`：同步明列 route running／paused、主要操作 baseline 與 pause／resume／stop probe 的驗證範圍。
- Post-fix targeted validation：`testConnectedSidebarRelayoutsObservedSimulationStates` 通過。
- Post-fix mechanical self-check：`git diff --check` 通過；artifact 中 idle、busy、route running、route paused、stopping failure 的狀態集合一致。

## Decision

next_round
