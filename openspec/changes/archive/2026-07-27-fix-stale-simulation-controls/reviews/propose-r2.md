# Cash Propose Review — Round 2

## Reviewer Findings

### Critical

None.

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `proposal.md`「Impact」、`design.md`「Implementation Contract」、`tasks.md` 1.1、`iPhoneLocationMove.xcodeproj/project.pbxproj`；`summary`: 新增的 `ContentViewTests.swift` 未規劃加入明確管理 Sources build phase 的 Xcode test target，因此檔案可能不被編譯或執行；`recommendation`: 將 `project.pbxproj` 納入 structured scope 並要求把新測試註冊至 `iPhoneLocationMoveTests` target；`disposition`: fix-introduced；`introduced_by`: Round 1 Fix Actions 新增獨立 `ContentViewTests.swift`，但未同步 target registration；reviewer source: Reviewer V — Verification。

### Suggestion

None.

## Rating

- cumulative blocking Critical: 0
- cumulative blocking Warning: 1
- non-blocking triaged finding: 0
- `critical_gap`: false
- `round_type`: micro
- Reviewer V 明確確認 Round 1 member resolved，故將其移出 cumulative blocking set；本輪修正引入的 Xcode target registration 缺口以 100 confidence 成為新的 blocking Warning，必須修正並再次驗證。

## Fix Actions

- Verified resolution removal：Round 1「shared store reference 測試無法證明 view invalidation」已由 Reviewer V 確認 resolved，依 Round 1 的 hosting hierarchy／accessibility identifier fix 移出 cumulative blocking set。
- 修改 `proposal.md`：將 `iPhoneLocationMove.xcodeproj/project.pbxproj` 加入 affected code structured scope。
- 修改 `design.md`：明定新測試檔必須加入 `iPhoneLocationMoveTests` group、file reference 與 Sources build phase。
- 修改 `tasks.md`：在 TDD task 中同步建立測試與 target registration，並先確認 test target 實際編譯執行該 failing test。
- Post-fix mechanical self-check：spec annotation／separator 與 `project.pbxproj`、`ContentViewTests.swift`、Sources build phase identifier propagation 均一致；重新執行 `cash validate` 通過，未需額外修正。

## Decision

next_round
