# Cash Apply Review — Round 6

## Reviewer Findings

### Critical

None.

### Warning

- severity: Warning
  confidence: 100
  layer: design
  location: `iPhoneLocationMoveTests/ContentViewTests.swift`、`iPhoneLocationMove/Features/Map/LocationMapView.swift`
  summary: toggle 尚未有直接可見 title 的 rendered oracle。
  recommendation: 補上同一 hierarchy 對 production button title 的直接或等價語義驗證。
  reviewer source: Reviewer V
  disposition: unresolved-prior

- severity: Warning
  confidence: 100
  layer: design
  location: `iPhoneLocationMoveTests/ContentViewTests.swift`
  summary: delete 後雖已驗證 preview 與 active `SimulationStore.state`，仍未直接驗證 map annotation 存在、座標與角色不變。
  recommendation: 在 connected hierarchy 取得 `MKMapView`，於 rendered delete action 前後比較對應 annotation。
  reviewer source: Reviewer V
  disposition: unresolved-prior

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 2
- non-blocking triaged finding count: 0
- critical_gap: false
- round_type: micro
- rationale: rename／blank rename 與其他主要 contract 已有測試，但 toggle title 與 delete annotation oracle 的累積 blocking findings 在第六輪仍未解決，依 cap 必須 abort。

## Fix Actions

- bucket 1 — remains this change's obligation：toggle 可見 title oracle、delete 後 annotation oracle；未接受為 risk，需後續修復後以 `$cash-apply add-favorites` re-run。
- Round 6 相關 tests 維持 `XCODEBUILD_STATUS:0`，但測試證據缺口不因 suite 通過而解除。

## Decision

aborted
