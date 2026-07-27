# Cash Propose Review — Round 5

## Reviewer Findings

### Critical

1. `severity`: Critical；`confidence`: 100；`layer`: design；`disposition`: fix-introduced；`introduced_by`: Round 2「Non-blocking triage與修正：clear cleanup ownership test gap」；`location`: `proposal.md` Proposed Solution／Capabilities、`design.md` Goals與「route progress 與 position knowledge」、`specs/device-tunnel-recovery/spec.md` recovery terminal requirement、`specs/location-simulation/spec.md`「可恢復 transport closure 的中斷判定」、`tasks.md` 3.3；`summary`: clear recovery failure的terminal state未完整傳播，部分總括文字要求所有recovery failure進入`interrupted(positionUnknown)`，但clear-specific contract同時要求保持stopping／cleanup ownership與retry clear，形成互斥實作要求；`recommendation`: 所有terminal wording拆成active `set` failure進入`interrupted(positionUnknown)`，`clear` failure保持stopping／cleanup ownership與retry clear，UI不得顯示running、idle或已恢復真實定位；reviewer source: Reviewer A。

### Warning

None.

### Suggestion

None.

## Rating

- Post-filter cumulative blocking Critical count: 1
- Post-filter cumulative blocking Warning count: 0
- Non-blocking triaged finding count: 0
- `critical_gap`: true
- `round_type`: full

Reviewer A與Reviewer B都確認Round 4的candidate identity建立順序 blocker已resolved。Reviewer A在full checkpoint發現Round 2 clear-cleanup修正未完整傳播的互斥terminal contract；Reviewer B未報告其他finding。此`fix-introduced` Critical保留為blocking，修正後須再由fresh Reviewer V驗證。

## Fix Actions

- Verified resolution removal：Round 4 candidate identity建立順序finding經Reviewer A與Reviewer B一致確認resolved；pending generation＋lease ID、DVT handle後完整identity與pre-identity cleanup已跨design／spec／tasks同步。
- 修正clear terminal-state propagation：修改`proposal.md`、`design.md`、`tasks.md`、`specs/device-tunnel-recovery/spec.md`與`specs/location-simulation/spec.md`，統一active `set` terminal failure進入`interrupted(positionUnknown)`，`clear` terminal failure保持stopping／cleanup ownership與retry clear，且不得回idle或宣稱已恢復真實定位。
- Post-fix mechanical self-check：兩份delta spec的annotation配對正常；`set`／`clear` recovery terminal語意已跨proposal／design／specs／tasks同步；location-simulation新增直接clear-failure scenario；所有open signals均無`check`欄位。
- Post-fix validation：`cash validate recover-dropped-device-tunnel`通過。

## Decision

next_round

blocking Critical已有跨artifact fix，但依cumulative-set規則必須由下一輪fresh Reviewer V確認resolved後才能移出。
