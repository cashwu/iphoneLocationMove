# Cash Propose Review — Round 3

## Reviewer Findings

### Critical

None.

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`disposition`: fix-introduced；`introduced_by`: `propose-r2.md` `## Fix Actions` 中「加入 `pausing`／correction transaction」及「要求 `pausing` 等待 in-flight」；`location`: `design.md` pause／sleep、`specs/location-simulation/spec.md` update barrier／sleep、`tasks.md` 5.3；`summary`: 一般 pause 已要求完整 `pausing` transaction，但既有 sleep contract 仍直接進入 paused，可能在 in-flight `set` 完成前誤報暫停；`recommendation`: sleep 走相同 transaction，睡前未完成則維持 `pausing`，wake 後確認或進入 `interrupted(positionUnknown)`；reviewer source：Reviewer V — Verification。

### Suggestion

None.

## Rating

- post-filter cumulative blocking Critical: 0
- post-filter cumulative blocking Warning: 1
- non-blocking triaged finding: 0
- `critical_gap`: false
- `round_type`: micro
- 理由：Reviewer V 已驗證移除 C1 與 W6；W5 的 Round 2 fix 在 sleep path 引入一個直接矛盾，因此以 `fix-introduced` 保留在 cumulative blocking set。修正後仍需 Round 4 full checkpoint 兩位 reviewers 都確認 resolved。

## Fix Actions

- verified resolution removal：C1 privileged runtime provenance／integrity；Round 2 trust-anchor fix 已由 Reviewer V 驗證。
- verified resolution removal：W6 tunnel lease／crash／reconcile exact contract；Round 2 contract fix 已由 Reviewer V 驗證。
- 修改 `design.md`：把 `pausing` 加入 state machine，並要求 sleep 使用與手動 pause 相同 transaction；睡前未完成時維持 `pausing`，wake 後確認，結果不確定則 `interrupted(positionUnknown)`。
- 修改 `specs/location-simulation/spec.md`：同步 sleep requirement 與 scenario，不再於 notification 後直接宣稱 paused。
- 修改 `tasks.md`：task 5.3 加入 sleep-during-in-flight、correction、wake confirmation 與 uncertain-result tests。
- 修正後機械自檢發現並修正 `specs/location-simulation/spec.md` requirement 首句仍寫「wake 後保持 paused」的 stale wording；已同步為完整 `pausing` transaction。
- 修正後機械自檢通過：annotation 均為 `0/0`、無 stray separator、18 個 requirements／67 個 scenarios／2 個 examples／24 個 tasks 的來源計數已重算、sleep／wake／pausing identifiers 跨 artifacts 一致、沒有 MODIFIED／REMOVED title identity 或 open signal check。
- 修正後 `cash validate add-macos-location-simulator` 通過。

## Decision

next_round
