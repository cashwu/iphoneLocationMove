# Cash Apply Review — Round 2

## Reviewer Findings

### Critical

None.

### Warning

- severity: Warning
  confidence: 100
  layer: design
  location: `iPhoneLocationMoveTests/ContentViewTests.swift`、`openspec/changes/add-favorites/tasks.md:5`
  summary: 累積 member 仍未完整驗證 rename／空白 rename 的 view 互動與刪除後 annotation／simulation 邊界。
  recommendation: 補上同一 rendered hierarchy 的對應互動或等價 observable state 測試。
  reviewer source: Reviewer V
  disposition: unresolved-prior

### Suggestion

None.

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 1
- non-blocking triaged finding count: 0
- critical_gap: false
- round_type: micro
- rationale: Round 1 的 preview-address stale finding 已由 Reviewer V 確認 resolved；task 1.3 的 rename／空白 rename／刪除邊界仍缺少完整 UI oracle，故需下一輪。

## Fix Actions

- 修復 `iPhoneLocationMove/Features/Map/LocationMapView.swift`：將最愛列選取 action 抽成 production path helper，並加入 DEBUG marker 直接觸發相同 action。
- 修復 `iPhoneLocationMoveTests/ContentViewTests.swift`：補上最愛列選取後 preview、stale search、cancellation counts 與同一 hierarchy reset／mutation 狀態驗證。
- Round 2 結束後執行指定 change tests，結果為 `XCODEBUILD_STATUS:0`。
- 累積 blocking member 的 rename／空白 rename 與刪除後 annotation／simulation 完整 interaction oracle 尚未達成，保留至下一輪。

## Decision

next_round
