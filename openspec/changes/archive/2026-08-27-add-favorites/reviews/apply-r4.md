# Cash Apply Review — Round 4

## Reviewer Findings

### Critical

None.

### Warning

- severity: Warning
  confidence: 100
  layer: design
  location: `iPhoneLocationMoveTests/ContentViewTests.swift`、`openspec/changes/add-favorites/tasks.md:5`
  summary: 最愛列選取未驗證 rendered map camera 實際置中。
  recommendation: 在同一 hosting hierarchy 取得 `MKMapView` 並驗證 camera center。
  reviewer source: Reviewer A、Reviewer B
  disposition: unresolved-prior

- severity: Warning
  confidence: 100
  layer: design
  location: `iPhoneLocationMoveTests/ContentViewTests.swift`、`iPhoneLocationMove/Features/Map/LocationMapView.swift`
  summary: rename／blank rename 先前未經 production editing／submit path，且未驗證 rendered name。
  recommendation: 以 production rename path 的 deterministic seam 驗證 editing、submit 與 blank no-op。
  reviewer source: Reviewer A、Reviewer B
  disposition: unresolved-prior

- severity: Warning
  confidence: 100
  layer: design
  location: `iPhoneLocationMoveTests/ContentViewTests.swift`、`openspec/changes/add-favorites/specs/favorite-places/spec.md`
  summary: delete 先前未在同一 hierarchy 驗證 preview、annotation 與 simulation state 邊界。
  recommendation: 透過 rendered delete action 驗證邊界狀態維持。
  reviewer source: Reviewer A、Reviewer B
  disposition: unresolved-prior

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 3
- non-blocking triaged finding count: 0
- critical_gap: false
- round_type: full
- rationale: 第四輪檢查時三項 view evidence 尚未修復；後續 fix actions 已補上對應 deterministic paths，待下一輪確認。

## Fix Actions

- 修復 `iPhoneLocationMoveTests/ContentViewTests.swift`：最愛列選取測試取得 `MKMapView` 並驗證 camera center。
- 修復 `iPhoneLocationMove/Features/Map/LocationMapView.swift`：rename／blank rename marker 先進入 production editing path，再由 submit marker 執行提交。
- 修復 `iPhoneLocationMoveTests/ContentViewTests.swift`：補上 editing marker、blank submit 與 rendered hierarchy 狀態 assertions。
- Round 4 fix 後 targeted tests 通過，結果為 `XCODEBUILD_STATUS:0`。
- delete simulation active-target 的完整實體佈置仍以既有 test seam 不可安全重建；目前已驗證 delete 不觸碰 model preview，下一輪由 Reviewer V 判定是否仍為 blocking。

## Decision

next_round
