# Cash Propose Review — Round 4

## Reviewer Findings

### Critical

None.

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`disposition`: fix-introduced；`introduced_by`: Round 3「修正candidate replay blocker」；`location`: `design.md`「將 logical device session 與可替換 transport identity 分離」、「單次 transport recovery transaction」步驟5；`summary`: `CandidateTransportIdentity`包含candidate generation、lease ID與DVT handle，但原步驟在candidate DVT helper啟動前就宣稱取得完整identity，建立順序自相矛盾；`recommendation`: tunnel啟動後先保存candidate generation與lease ID，ownership gate通過並取得DVT handle後才組成完整identity，且完整identity建立前失敗仍清理已取得的candidate資源；reviewer source: Reviewer V。

### Suggestion

None.

## Rating

- Post-filter cumulative blocking Critical count: 0
- Post-filter cumulative blocking Warning count: 1
- Non-blocking triaged finding count: 0
- `critical_gap`: false
- `round_type`: micro

Reviewer V逐項確認Round 3的candidate pre-commit gate與device switch suspension test blockers均已resolved；但`CandidateTransportIdentity`的完整欄位與建立時機是Round 3 fix引入的直接矛盾，因此以blocking `fix-introduced` Warning保留，修正後進入本次loop run第4位置的full checkpoint。

## Fix Actions

- Verified resolution removal：Round 3 candidate replay current-gate finding經Reviewer V確認resolved；candidate reply使用transaction-scoped identity形成local result，atomic commit前不發布logical success。
- Verified resolution removal：Round 3 device switch test gap經Reviewer V確認resolved；`design.md`與`tasks.md`已直接要求candidate tunnel ready邊界的device switch插入與old-device clear assertions。
- 修正candidate identity建立順序：修改`design.md`、`tasks.md`與`specs/device-tunnel-recovery/spec.md`，明定tunnel啟動後先保存pending candidate generation＋lease ID，DVT helper成功並取得handle後才建立完整`CandidateTransportIdentity`；完整identity建立前失敗仍須清理已取得資源。
- Post-fix mechanical self-check：兩份delta spec的annotation配對正常；pending candidate lease、DVT handle、完整identity、replay與cleanup語意已跨design／spec／tasks同步；所有open signals均無`check`欄位。
- Post-fix validation：`cash validate recover-dropped-device-tunnel`通過。

## Decision

next_round

blocking Warning已有明確fix，但依cumulative-set規則須由下一輪reviewer確認resolved；下一輪是本次loop run第4位置，因此執行full checkpoint。
