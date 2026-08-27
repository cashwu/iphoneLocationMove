# Cash Apply Review — Round 5

## Reviewer Findings

### Critical

None.

### Warning

- severity: Warning
  confidence: 100
  layer: design
  location: `iPhoneLocationMoveTests/ContentViewTests.swift:33-61`
  summary: toggle 測試仍未直接斷言可見 production button title。
  recommendation: 增加 rendered semantic label assertion。
  reviewer source: Reviewer V
  disposition: unresolved-prior

- severity: Warning
  confidence: 100
  layer: design
  location: `iPhoneLocationMoveTests/ContentViewTests.swift:129-155`
  summary: rename／blank rename 尚未以 rendered row name 作為 oracle。
  recommendation: 增加 row-name rendered identifier assertion。
  reviewer source: Reviewer V
  disposition: unresolved-prior

- severity: Warning
  confidence: 100
  layer: design
  location: `iPhoneLocationMoveTests/ContentViewTests.swift:129-160`
  summary: delete 尚未驗證 annotation 與 active SimulationStore state。
  recommendation: 在 connected hierarchy 補上兩項 state assertion。
  reviewer source: Reviewer V
  disposition: unresolved-prior

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 3
- non-blocking triaged finding count: 0
- critical_gap: false
- round_type: micro
- rationale: round 5 review 發現三項 view oracle 尚不完整；其後已補 semantic toggle 與 rendered row-name assertions，delete simulation boundary 仍待最終確認。

## Fix Actions

- 修復 `iPhoneLocationMove/Features/Map/LocationMapView.swift`：加入依語義變化的 toggle accessibility identifier 與依名稱變化的 row-name rendered region。
- 修復 `iPhoneLocationMoveTests/ContentViewTests.swift`：補上 toggle semantic label 與 row-name assertions；delete fixture 建立 point-active `SimulationStore` 並比較 state。
- 修復後相關測試已通過，結果為 `XCODEBUILD_STATUS:0`。

## Decision

next_round
