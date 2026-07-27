# Cash Propose Review — Round 3

## Reviewer Findings

### Critical

1. `severity`: Critical；`confidence`: 100；`layer`: design；`disposition`: fix-introduced；`introduced_by`: Round 2「修正blocking actor reentrancy finding」；`location`: `design.md`「將 logical device session 與可替換 transport identity 分離」、「單次 transport recovery transaction」；`summary`: 一般reply規則要求transport generation必須current，但candidate replay發生在candidate generation commit成current之前，依原文字會先被判為stale；`recommendation`: 使用transaction-scoped candidate identity驗證candidate reply，只保存transaction-local result，待ownership重驗證與candidate atomic commit後才發布logical success；reviewer source: Reviewer V。

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`disposition`: fix-introduced；`introduced_by`: Round 2「修正blocking actor reentrancy finding」；`location`: `design.md` Implementation Contract 6、`tasks.md` 1.3；`summary`: recovery suspension matrix只明列disconnect、quit與reconnect，未直接測試device switch插入candidate recovery的情境；`recommendation`: 至少在candidate tunnel ready邊界插入device switch，驗證epoch先失效、舊recovery不重播、candidate回收且old-device clear仍使用正確transport identity；reviewer source: Reviewer V。

### Suggestion

None.

## Rating

- Post-filter cumulative blocking Critical count: 1
- Post-filter cumulative blocking Warning count: 1
- Non-blocking triaged finding count: 0
- `critical_gap`: true
- `round_type`: micro

Reviewer V確認Round 2的transport identity／recovery cancellation blocker已由獨立`RecoveryOwnershipEpoch`解決，但發現該修正缺少device switch邊界測試，且candidate replay與current-generation gate存在矛盾。兩項均位於Round 2 fix-touched概念，依disposition規則列為blocking `fix-introduced`，修正後須由下一位fresh Reviewer V確認。

## Fix Actions

- Verified resolution removal：Round 2 blocking identity／cancellation finding經Reviewer V確認resolved；`RecoveryOwnershipEpoch`只取消recovery transaction，`DeviceTransportGeneration`只識別tunnel／DVT pair，old-device clear不會被提前判為stale。
- Disposition correction：Reviewer V將candidate replay finding標為`new`；主代理檢查後改為`fix-introduced`，因缺陷位於Round 2新增的transport identity／recovery ownership規則，且是該fix對candidate pre-commit reply ordering未完整定義所致。
- 修正candidate replay blocker：修改`design.md`、`tasks.md`與`specs/device-tunnel-recovery/spec.md`，新增transaction-scoped `CandidateTransportIdentity`；candidate reply只形成transaction-local result，不套用current-transport gate，且ownership重驗證與atomic commit前不得發布logical success。
- 修正device switch test gap：修改`design.md`與`tasks.md`，要求至少在candidate tunnel ready邊界插入device switch，驗證recovery epoch失效、candidate cleanup、禁止stale replay及old-device clear ownership。
- Post-fix mechanical self-check：兩份delta spec的annotation配對正常；`CandidateTransportIdentity`、`RecoveryOwnershipEpoch`、candidate pre-commit reply、atomic commit與device switch suspension已跨design／specs／tasks同步；所有open signals均無`check`欄位。
- Post-fix validation：`cash validate recover-dropped-device-tunnel`通過。

## Decision

next_round

兩項blocking `fix-introduced` findings均已有明確fix，但依cumulative-set規則，須由下一輪fresh Reviewer V逐項確認resolved後才能移出。
