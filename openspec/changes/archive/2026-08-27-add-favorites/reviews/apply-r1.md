# Cash Apply Review — Round 1

## Reviewer Findings

### Critical

None.

### Warning

- severity: Warning
  confidence: 100
  layer: design
  location: `openspec/changes/add-favorites/tasks.md:5`、`iPhoneLocationMoveTests/ContentViewTests.swift`
  summary: task 1.3 原要求的最愛列選取、ownership gate 後取消 async、rename、空白 rename、刪除後維持 preview／simulation 狀態、reset 保留最愛等 view regression tests 尚未完整覆蓋。
  recommendation: 補齊同一 rendered hierarchy 的測試，並直接觀察 production cancellation path。
  reviewer source: Reviewer A、Reviewer B
  disposition: unresolved-prior

- severity: Warning
  confidence: 100
  layer: design
  location: `openspec/changes/add-favorites/tasks.md:4`、`iPhoneLocationMoveTests/LocationMapModelTests.swift`
  summary: task 1.2 原要求的舊 `preview-address` 回應 stale 案例在本輪前尚未覆蓋。
  recommendation: 補上舊 reverse-geocode request 在選用最愛後被判定 stale 且不覆寫 preview 的測試。
  reviewer source: Reviewer A
  disposition: unresolved-prior

### Suggestion

- severity: Suggestion
  confidence: 85
  layer: design
  location: `iPhoneLocationMove/ContentView.swift`、`iPhoneLocationMove/Features/Map/LocationMapView.swift`
  summary: `favoritesStore` 仍在 `LocationWorkspaceView` 保留測試便利的預設值。
  recommendation: 若要完全強制注入，移除 workspace initializer 的預設值並更新既有測試 fixture。
  reviewer source: Reviewer B

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 2
- non-blocking triaged finding count: 1
- critical_gap: false
- round_type: full
- rationale: 既有 implementation 通過編譯與測試，但 task 1.2／1.3 的 view 與 stale-response 驗證證據尚不完整，兩項 Warning 仍屬本 change obligation，故需進入下一輪。

## Fix Actions

- 修復 `iPhoneLocationMoveTests/ContentViewTests.swift`：補上收藏 toggle 在同一 rendered hierarchy 中加入與取消的雙向切換驗證。
- 修復 `iPhoneLocationMoveTests/LocationMapModelTests.swift`：補上選用最愛後舊 `MapPreviewAddressRequest` response 為 `.stale` 的驗證。
- 修復 `iPhoneLocationMove/Features/Map/LocationMapView.swift`：移除兩個 `LocationMapView` production initializer 的 `favoritesStore` 預設值，避免省略注入時建立隔離 owner。
- Suggestion 維持 non-blocking triage：`LocationWorkspaceView` 的預設值只供既有測試 fixture 使用，App production path 已明確傳遞 `appDelegate.favoritesStore`；不改變 observable contract。
- 本輪未修復：task 1.3 所列 rename／空白 rename／最愛列選取 cancellation／刪除邊界／reset 保留的完整 rendered-hierarchy 測試，列為下一輪 blocking obligation。

## Decision

next_round
