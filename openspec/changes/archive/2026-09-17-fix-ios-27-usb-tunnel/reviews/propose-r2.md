# Cash Propose Review — Round 2

## Reviewer Findings

### Critical

（無）

### Warning

1. `severity`: Warning／`confidence`: 98／`layer`: design／來源：Reviewer V／`disposition`: unresolved-prior
   - `location`: `design.md` Decision 5／Implementation Contract 11、`tasks.md` 1.5、master spec `openspec/specs/ios-device-session/spec.md` production privileged acceptance scenario
   - `summary`: Round 1 finding 2 的完整 production suite修正漏掉 master spec強制的 `uninstall` 與 final cleanup oracle；既有清單未確認 system service、固定安裝 paths與相關 root process全部不存在。
   - `recommendation`: 將 `uninstall` 納入不可跳過 final phase，以固定 schema驗證 service、helper、plist、runtime parent與 root process全部不存在，並保存 evidence。

### Suggestion

（無）

Reviewer V 對 prior members 的 verdict：finding 1 resolved；finding 2 unresolved；finding 3 resolved；finding 4 resolved；finding 5 resolved。未發現其他 fix-introduced 或 new Critical／Warning。

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 1
- 非 blocking triaged finding count: 0
- `critical_gap`: false
- `round_type`: micro

rationale：Reviewer V 已驗證移除 Round 1 findings 1、3、4、5；finding 2 因 master cleanup contract傳播不完整仍留在 cumulative blocking set，因此本輪必須 `next_round`。

## Fix Actions

- finding 1（Round 1 finding 2 carryover）：修改 `design.md` 與 `tasks.md`，把 `uninstall` 定義為所有 required cases之後不可跳過的 final phase；固定輸出 `serviceAbsent`、`helperToolAbsent`、`launchDaemonPlistAbsent`、`runtimeParentAbsent`、`rootProcessesAbsent`，任一不是 `true` 則整體 fail，並要求結果寫入 `acceptance-results.md`。
- post-fix：`cash validate` 回報 `valid:true`；`cash analyze` 的 Coverage／Consistency／Gaps 皆 Clean，Ambiguity 只剩 9 筆非阻塞 Example suggestions；comment／separator、identifier propagation、title identity與 `git diff --check` 通過。
- 本輪只修改 change directory內 artifacts，無 change外路徑需執行 `cash touched record`。

## Decision

next_round
