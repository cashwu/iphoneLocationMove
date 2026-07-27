# Cash Apply Review — Round 1

## Reviewer Findings

### Critical

None.

### Warning

- `severity`: Warning
  `confidence`: 100
  `layer`: design
  `location`: `iPhoneLocationMove/Features/Map/MacLocationClient.swift:68-84`、`iPhoneLocationMoveTests/MacLocationClientTests.swift:141-168`
  `summary`: 已取消 task 在 request context 建立前會拋出未型別化的 `CancellationError`，不符合 typed cancellation terminal contract。
  `recommendation`: 在建立 request context 前明確轉成 `MacLocationClientError.cancelled`，並補 pre-cancelled 與 manager 建立期間取消的 deterministic tests。
  `introduced_by`: `iPhoneLocationMove/Features/Map/MacLocationClient.swift:68-84` 的 `Task.checkCancellation()` 路徑與 `iPhoneLocationMoveTests/MacLocationClientTests.swift:141-168` 未覆蓋的 pre-cancelled case。
  reviewer source: Reviewer B — Quality

- `severity`: Warning
  `confidence`: 100
  `layer`: design
  `location`: `design.md`「Risks / Trade-offs」、`tasks.md` 3.4、`iPhoneLocationMove/Features/Map/LocationMapView.swift:1058` 與 `iPhoneLocationMove/Features/Map/LocationMapView.swift:1089`
  `summary`: canvas coordinator 未依 design 在 `setRegion`／`setVisibleMapRect` 執行期間標記 programmatic camera update。
  `recommendation`: 明確追蹤 programmatic camera update，讓 region change 只對非 programmatic 的 user gesture 回報。
  reviewer source: Reviewer A — Adherence

- `severity`: Warning
  `confidence`: 100
  `layer`: design
  `location`: `iPhoneLocationMove/Features/Map/LocationMapView.swift:946-1098`、`iPhoneLocationMoveTests/LocationMapModelTests.swift:391-418`
  `summary`: camera identity 與 manual interaction 只在 model 層驗證，未直接測試真正執行 camera effect 的 gate。
  `recommendation`: 補可控制 camera effect boundary，驗證同一 route identity 不重播、新 identity 會套用、programmatic change 不誤判、user gesture 會回報。
  `introduced_by`: `iPhoneLocationMove/Features/Map/LocationMapView.swift:946-1098` 新增的 camera paths 與 `iPhoneLocationMoveTests/LocationMapModelTests.swift:391-418` 僅檢查 model identity。
  reviewer source: Reviewer B — Quality

### Suggestion

None.

## Rating

- cumulative blocking Critical: 0
- cumulative blocking Warning: 3
- non-blocking triaged findings: 0
- `critical_gap`: false
- `round_type`: full
- rationale: 第一輪三項高信心 Warning 全部進入 cumulative blocking set；修正已完成，但仍需 fresh Reviewer V 驗證 resolution 與 fix propagation，因此本輪為 `next_round`。

## Fix Actions

- 修改 `iPhoneLocationMove/Features/Map/MacLocationClient.swift`：在任何 manager 建立前將 pre-cancelled task 映射為 `MacLocationClientError.cancelled`，並保留 continuation 安裝前的 cancellation guard。
- 修改 `iPhoneLocationMoveTests/MacLocationClientTests.swift`：新增呼叫前已取消與 manager 建立期間取消兩個 deterministic typed-error／ownership tests。
- 修改 `iPhoneLocationMove/Features/Map/LocationMapView.swift`：新增 `LocationMapCameraEffects`，集中保存 preview／route／Mac identity，並在 programmatic camera closure 執行期間標記 ownership。
- 修改 `iPhoneLocationMoveTests/LocationMapModelTests.swift`：直接驗證 route identity effect count、programmatic change 不回報 manual interaction，以及 active user gesture 會回報。
- 修正後重跑 targeted tests、`git diff --check`、annotation lint、identifier cross-grep 與 `cash validate`；全部通過。

## Decision

next_round
