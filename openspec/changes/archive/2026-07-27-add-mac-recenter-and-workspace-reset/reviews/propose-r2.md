# Cash Propose Review — Round 2

## Reviewer Findings

### Suggestion

- **V1** — severity: Suggestion, confidence: 60, layer: text, disposition: fix-introduced, introduced_by: Round 1 Fix Action W2
  - location: design.md Implementation Contract 執行順序句「清空兩個上移後的訊息 binding」
  - summary: 上移的訊息 state 只有一個（`SimulationControls.message`）；`LocationMapView.message` 本為自有 `@State` 未經上移，「兩個上移後的訊息 binding」數量敘述與 Decision 7 不合，可能誤導實作者。
  - recommendation: 改寫為「清空 `LocationMapView` 自有的 `message` 與上移後的 simulation `message` binding」。
  - 來源: Reviewer V
- **V2** — severity: Suggestion, confidence: 55, layer: design, disposition: fix-introduced, introduced_by: Round 1 Fix Action C1
  - location: specs/mac-map-initial-location/spec.md「重新連線更新位置」scenario 新增條件「其後未發生工作區重置」
  - summary: 新條件使「重置當下 Mac 位置已取得（未重新武裝）、其後重新連線」的組合不落入任何 scenario 的 WHEN，正確行為只能由 requirement 敘述句反面推得。
  - recommendation: 於該 scenario 條件註明含「重置當下 Mac 位置已取得因而未重新武裝」之情形。
  - 來源: Reviewer V

## Rating

- post-filter cumulative blocking set：Critical 0、Warning 0（4 個 member 全數 verified resolution 移除）
- non-blocking triaged findings：2（V1、V2，皆 Suggestion，不阻塞）
- critical_gap: false
- round_type: micro
- 理由：Reviewer V 對 cumulative blocking set 全部 4 個 member 回覆明確 resolved verdict（含 MODIFIED requirement 與 master 的逐字 diff 驗證、fix propagation 檢查與 S1–S7 抽查），僅回報兩筆 fix-introduced 的 Suggestion；blocking set 為空，符合 pass 條件。

## Fix Actions

verified-resolution 移除記錄（member／fix 參照／驗證者）：

- C1 — Round 1 Fix Action C1（MODIFIED requirement 補授權）— Reviewer V 驗證 resolved（與 master 逐字基底 diff 一致，僅三處刻意修改；與 location-simulation delta 行為一致）。
- W1 — Round 1 Fix Action W1（Decision 8 統一為獨立確認 state）— Reviewer V 驗證 resolved。
- W2 — Round 1 Fix Action W2（`roundTrip` 與 `message` 上移）— Reviewer V 驗證 resolved（並確認 `DisconnectedSimulationControls` 不動無虞）。
- W3 — Round 1 Fix Action W3（tasks 3.4 view 層測試＋警語純函式）— Reviewer V 驗證 resolved（四處 identifier 一致、hosting-view 模式存在）。

非阻塞 finding 之處置（本輪雖 passed，兩筆 fix-introduced Suggestion 屬廉價文字修正，直接修正以免誤導 cash-apply）：

- V1 → design.md Implementation Contract：改寫為「清空 `LocationMapView` 自有的 `message` 與上移後的 simulation `message` binding」；同步 tasks 2.3 同句。
- V2 → specs/mac-map-initial-location/spec.md：「重新連線更新位置」scenario 條件改為「其後未發生重新武裝初始置中的工作區重置（未發生重置，或重置當下 Mac 位置已取得因而未重新武裝）」。

修正檔案清單：design.md、tasks.md、specs/mac-map-initial-location/spec.md（均在 change 目錄內，無需 touched record）。

post-fix 驗證：「$cash_cli」validate add-mac-recenter-and-workspace-reset → Validation passed；MODIFIED requirement 標題與 master byte-for-byte 一致；無註解殘留。

## Decision

passed
