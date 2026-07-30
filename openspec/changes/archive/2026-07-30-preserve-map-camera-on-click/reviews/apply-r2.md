# Cash Apply Review — Round 2

## Reviewer Findings

### Critical

- `severity`: Critical
- `confidence`: 99
- `layer`: text
- `location`: `openspec/changes/preserve-map-camera-on-click/implementation-notes.md`「停用測試建置簽章」
- `summary`: `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` 已存在於 tasks 3.1／3.2 的原定命令，卻被誤記為 deviation，違反 Implementation Notes Protocol 的 narrow log。
- `recommendation`: 刪除該筆不成立的 deviation；保留兩筆真正替換 AppKit 驗證機制的 deviation。
- reviewer source：Reviewer A — Adherence

### Warning

無。

### Suggestion

無。

## Rating

- cumulative blocking Critical：1
- cumulative blocking Warning：0
- non-blocking triaged finding：0
- critical_gap：true
- round_type：full
- rationale：Reviewer A 確認 production、tests 與 Implementation Contract 一致，但發現一筆不成立的 deviation；Reviewer B 未發現程式品質問題。該 Critical 進入 cumulative blocking set，因此本輪不得通過。

## Fix Actions

- 已刪除 `implementation-notes.md` 中「停用測試建置簽章」整筆條目；task 原定命令本身已處理簽章，不屬 deviation。
- 自我檢查發現 marker regression test 將 MapKit 初次置中的 `setRegion` 次數綁死為 1，但實際為 2；已在 `iPhoneLocationMoveTests/LocationMapModelTests.swift` 改為斷言大於 0，仍能防止 camera apply 完全失效時的 0→0 假通過，且不綁定框架內部呼叫次數。

## Decision

next_round
