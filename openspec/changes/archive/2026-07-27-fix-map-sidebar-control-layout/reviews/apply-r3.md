# Cash Apply Review — Round 3

## Reviewer Findings

### Critical

無。

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`disposition`: fix-introduced；`introduced_by`: Round 1 Fix Actions 新增 route running／paused 狀態覆蓋時，未同步加入每狀態 marker oracle；`location`: `iPhoneLocationMoveTests/ContentViewTests.swift` 的 route running 與 route paused 驗證段落；`summary`: 兩段只呼叫 `assertSidebarLayout`，未呼叫 `assertTestingActionButtons`，因此條件式重排狀態沒有驗證 marker 的零尺寸、透明、focus 與 accessibility contract；`recommendation`: 在 running 與 paused 的 layout assertion 後各重跑 marker oracle，再執行 targeted stability test；reviewer source: Reviewer V — Verification。

### Suggestion

無。

## Rating

- post-filter cumulative blocking Critical count: 0
- post-filter cumulative blocking Warning count: 1
- non-blocking triaged finding count: 0
- `critical_gap`: false
- `round_type`: micro

Reviewer V 明確確認 Round 2 的 paused UI 同步 flake 已 resolved：timeout helper 同時等待 model phase 與 resume probe，成功後仍執行完整 layout oracle，且 targeted test 通過，因此該 cumulative member 已由 Reviewer V 驗證移除。本輪另發現一項由 Round 1 Fix Actions 引入的 marker oracle 缺口，加入 cumulative blocking set。修正已完成，但需下一輪 checkpoint reviewers 驗證後才能移除，因此本輪為 `next_round`。

## Fix Actions

- 修改 `iPhoneLocationMoveTests/ContentViewTests.swift`：在 route running 與 route paused 的 `assertSidebarLayout` 後分別呼叫 `assertTestingActionButtons`，確保每個條件式狀態都重跑 marker 的尺寸、透明度、focus ring、first responder 與 accessibility oracle。
- Post-fix stability validation：以 `-test-iterations 5` 連續執行 `testConnectedSidebarRelayoutsObservedSimulationStates`，5/5 全部通過。
- Post-fix validation：`cash validate fix-map-sidebar-control-layout` 與 `git diff --check` 通過；cross-grep 確認 running／paused layout oracle 後均緊接 marker oracle。

## Decision

next_round
