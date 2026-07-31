# Cash Apply Review — Round 1

## Reviewer Findings

### Critical

無。

### Warning

- severity: Warning
  confidence: 100
  layer: design
  location: `iPhoneLocationMoveTests/ContentViewTests.swift` 的 `testStaleRenderedSearchResultActionPreservesNewSearchOwnership()` 與 `testStaleRenderedSearchResultActionPreservesPreviewAddressOwnership()`；對應 `design.md` Implementation Contract 10 與 `tasks.md` 1.2
  summary: stale action tests 只建立 model ownership 並手動套用 response，未建立或觀察 `LocationMapView` 的 cancellation path，因此即使 view 錯誤呼叫 `cancelSearch()` 或 `cancelPreviewAddressLookup()`，測試仍可能通過。
  recommendation: 以最小 cancellation observer seam 連到相同 production cancellation functions，讓同一 rendered hierarchy 直接斷言 stale action 未進入兩個取消路徑，再驗證 response 可套用。
  reviewer source: Reviewer A — Adherence、Reviewer B — Quality
  introduced_by: `iPhoneLocationMoveTests/ContentViewTests.swift` 本次新增的兩個 stale-action tests及其直接 model setup/response 路徑

### Suggestion

無。

Reviewer A 確認 `implementation-notes.md` 的 task 1.2 red-verification sequencing deviation 合理；其餘 Implementation Contract 1–9 均符合。Reviewer B 對 membership gate、validate-before-cancel ordering、camera intent、annotation identity、camera replay 與 DEBUG marker 未發現其他問題。

## Rating

- post-filter cumulative blocking Critical: 0
- post-filter cumulative blocking Warning: 1
- non-blocking triaged finding: 0
- critical_gap: false
- round_type: full
- rationale: 兩位 reviewers 獨立指出同一個 100-confidence test-oracle 缺口，直接違反 Implementation Contract 10，因此納入 cumulative blocking set。已以相同 production cancellation functions 的 observer seam 修正並通過 tests，仍需 fresh Reviewer V 驗證修正有效且未引入新缺陷。

## Fix Actions

- 修改 `openspec/changes/fix-repeat-search-result-selection/implementation-notes.md`：記錄以 internal cancellation observer 取代不可控制 concrete MapKit/CLGeocoder spy 的 contract-preserving deviation。
- 修改 `iPhoneLocationMove/Features/Map/LocationMapView.swift`：在 initializer 加入預設 no-op 的 `onSearchCancellation` 與 `onPreviewAddressCancellation` observers，並由既有 `cancelSearch()`、`cancelPreviewAddressLookup()` production paths 呼叫。
- 修改 `iPhoneLocationMoveTests/ContentViewTests.swift`：成功選取案例先證明兩個 observers 確實連到取消路徑；兩個 stale-action cases 再直接斷言 observer counts 不變，並保留 response 可套用 assertions。
- 執行 `ContentViewTests`，結果 `TEST SUCCEEDED`。
- 重跑完整 `xcodebuild test` suite，結果 `TEST SUCCEEDED`。
- 修正後機械式自檢通過：spec annotation/title identity、identifier propagation、signal-derived manual checks、`git diff --check` 與 Cash validation 均通過；所有 open signals 均無 `check` field 可執行。
- 已以 Cash touched state 記錄 `iPhoneLocationMove/Features/Map/LocationMapView.swift` 與 `iPhoneLocationMoveTests/ContentViewTests.swift`。

## Decision

next_round
