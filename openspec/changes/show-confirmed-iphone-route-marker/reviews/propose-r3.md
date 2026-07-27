# Cash Propose Review — Round 3

## Reviewer Findings

### Critical

None.

### Warning

- severity: Warning
  confidence: 100
  layer: design
  location: `proposal.md` Motivation、Proposed Solution；`design.md` Context、Decisions 1–2、Implementation Contract 2
  summary: proposal與design Context仍稱`RouteSimulationSnapshot.confirmedCoordinate`是唯一來源，但stopping state沒有route snapshot，與已改為讀取同一`RouteSession.confirmedCoordinate`的contract矛盾。
  recommendation: 將剩餘文字統一為route confirmed truth，明列route state讀snapshot、stopping state讀同一route session。
  disposition: unresolved-prior
  reviewer: Reviewer V

### Suggestion

None.

## Rating

- Critical: 0
- Warning: 1
- Non-blocking triaged findings: 0
- critical_gap: false
- round_type: micro
- rationale: position-unknown→stopping成員已由Reviewer V驗證解除；confirmed source wording成員仍在proposal與design Context存在，因此cumulative blocking set保留一個Warning，必須修正後進入第四輪full checkpoint。

## Fix Actions

- Verified resolution removal：移除Round 2「position-unknown route後續stopping重新顯示marker」成員；Reviewer V確認`RouteSession.requestStop()`與`clearFailed()`保留interruption，且artifacts要求projection延續knowledge gate。
- disposition correction：Reviewer V原標記`fix-incomplete`不在允許值集合；依同一artifact位置與同一來源contract矛盾機制，修正為`unresolved-prior`。
- 修正 `proposal.md`、`design.md`：將Motivation、Proposed Solution與Context統一為同一`RouteSession`的route confirmed truth；route state讀`RouteSimulationSnapshot.confirmedCoordinate`，stopping state讀`RouteSession.confirmedCoordinate`。
- 重新執行 `.cash-skills/bin/cash validate show-confirmed-iphone-route-marker`：`Validation passed`。
- post-fix mechanical self-check：confirmed source identifier cross-grep、spec annotation count與separator lint均通過。

## Decision

next_round
