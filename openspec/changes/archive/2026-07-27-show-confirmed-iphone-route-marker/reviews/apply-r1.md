# Cash Apply Review — Round 1

## Reviewer Findings

### Critical

None.

### Warning

- severity: Warning
  confidence: 90
  layer: design
  location: `iPhoneLocationMoveTests/ContentViewTests.swift:22-31`
  summary: 同一 annotation identity更新測試在觸發tick後才從可變的`initialAnnotation.coordinate.longitude`讀取比較基準，存在排程競態；device completion若先更新同一instance，測試會等待不存在的下一次座標變化並逾時。
  recommendation: 在`tick(at:)`前先將初始longitude複製到不可變local value，之後將該snapshot傳給`waitForRouteMarker`；仍以`initialAnnotation === updatedAnnotation`驗證identity。
  introduced_by: `iPhoneLocationMoveTests/ContentViewTests.swift:22`保存可變annotation reference，`:28-31`在async device call開始後重新讀取其coordinate作為舊值。
  reviewer: Reviewer B — Quality

### Suggestion

None.

## Rating

- Critical: 0
- Warning: 1
- Non-blocking triaged findings: 0
- critical_gap: false
- round_type: full
- rationale: 這是unseeded run的第一輪；唯一surviving Warning信心為90，依規則進入cumulative blocking set，因此本輪必須修正並由下一輪micro Reviewer V驗證。

## Fix Actions

- 修正 `iPhoneLocationMoveTests/ContentViewTests.swift`：在`tick(at:)`前以`initialLongitude`快照初始coordinate，避免同一可變annotation instance先被publisher更新後污染比較基準。
- 重新執行 `ContentViewTests/testConfirmedRouteMarkerUpdatesSameAnnotationInSameHostingView`：`TEST SUCCEEDED`。
- 重新執行完整 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS'`：`TEST SUCCEEDED`。
- post-fix mechanical self-check：spec annotation count、requirement／scenario／task count、`initialLongitude` identifier propagation與`git diff --check`均通過。
- 已以 `cash touched record` 記錄 `iPhoneLocationMoveTests/ContentViewTests.swift`。

## Decision

next_round
