# Cash Apply Review — Round 1

## Reviewer Findings

### Critical

- severity: Critical
  confidence: 100
  layer: design
  location: `iPhoneLocationMove/Features/Map/LocationMapView.swift:658-696`、`iPhoneLocationMoveTests/ContentViewTests.swift:370-378`、`openspec/changes/add-mac-recenter-and-workspace-reset/implementation-notes.md`
  summary: Production `AccessibilityActionMarker` 直接執行 `performReset`，提供繞過必要確認對話框的重置路徑，且 hosting test 只驗證該旁路。
  recommendation: 所有 Reset 入口皆先呼叫 `presentResetConfirmation`；測試 seam 不得建立使用者可觸發的 production 旁路，並應驗證確認前不重置、確認後才重置。
  introduced_by: `iPhoneLocationMove/Features/Map/LocationMapView.swift` 新增的 `AccessibilityActionMarker(action: performReset)`，以及 `iPhoneLocationMoveTests/ContentViewTests.swift` 新增的 `confirmReset` marker click。
  reviewer source: Reviewer A — Adherence、Reviewer B — Quality

### Warning

無。

### Suggestion

無。

## Rating

- Critical: 1
- Warning: 0
- Non-blocking triaged findings: 0
- critical_gap: true
- round_type: full

兩位 reviewer 獨立回報同一個確認旁路，依 `location + summary` 合併並採較高的 Critical；unseeded first round 的 surviving Critical 進入 cumulative blocking set，因此本輪必須修正並由下一輪驗證。

## Fix Actions

- 修改 `iPhoneLocationMove/Features/Map/LocationMapView.swift`：將 testing seam 改為 DEBUG-only `TestingActionMarker` 並從 accessibility tree 隱藏；Reset marker 僅呼叫 `presentResetConfirmation`，confirmation marker 僅在 `isResetConfirmationPresented == true` 時才能呼叫確認後 reset；Release build 不包含 testing marker。
- 修改 `iPhoneLocationMoveTests/ContentViewTests.swift`：hosting flow 在 Reset action 後先斷言 query、roundTrip、端點與 route 尚未改變，再觸發 confirmation marker，最後驗證重置。
- 修改 `openspec/changes/add-mac-recenter-and-workspace-reset/implementation-notes.md`：追加 follow-up deviation，明確記錄原判斷錯誤與修正後的 contract 邊界。
- 驗證：`ContentViewTests` 全數通過；完整 `iPhoneLocationMove` scheme 為 191 tests、0 failures；Release build succeeded。
- Post-fix mechanical self-check：spec 註解配對、stray separator、MODIFIED requirement title identity、identifier cross-grep 與 `git diff --check` 全數通過；所有 open signals 均無 `check` 欄位。
- Touched state：已記錄 `iPhoneLocationMove/Features/Map/LocationMapView.swift`、`iPhoneLocationMoveTests/ContentViewTests.swift`。

## Decision

next_round
