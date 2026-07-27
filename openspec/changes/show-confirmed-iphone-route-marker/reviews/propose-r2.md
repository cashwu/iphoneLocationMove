# Cash Propose Review — Round 2

## Reviewer Findings

### Critical

- severity: Critical
  confidence: 100
  layer: design
  location: `design.md` Decisions 1–2、Implementation Contract 5–6；`specs/location-simulation/spec.md` position-unknown lifecycle；`tasks.md` 1.3、2.1
  summary: position-unknown route進入`.stopping`後，projection若無條件讀取保留的`routeSession.confirmedCoordinate`，會重新顯示已不可信marker。
  recommendation: `.stopping` projection必須延續`routeSession.interruption?.positionKnowledge` gate，並測試unknown interruption後stop、clear pending與clear failure均保持marker移除。
  disposition: fix-introduced
  introduced_by: Round 1 Fix Actions「stopping／clear failure讀取既有route session confirmed coordinate」
  reviewer: Reviewer V

### Warning

- severity: Warning
  confidence: 99
  layer: design
  location: delta spec requirement preamble；`design.md` Decisions 1–2、Implementation Contract 2；`tasks.md` 2.1
  summary: marker coordinate被要求唯一來自`RouteSimulationSnapshot.confirmedCoordinate`，但`.stopping`沒有route snapshot，與讀取`routeSession.confirmedCoordinate`的修正矛盾。
  recommendation: 將來源contract統一為route已確認truth；`.route`讀snapshot，`.stopping`讀同一route session保留的confirmed coordinate。
  disposition: fix-introduced
  introduced_by: Round 1 Fix Actions「統一stop lifecycle並保留stopping marker」
  reviewer: Reviewer V

### Suggestion

None.

## Rating

- Critical: 1
- Warning: 1
- Non-blocking triaged findings: 0
- critical_gap: true
- round_type: micro
- rationale: Reviewer V確認Round 1的stop lifecycle、overlay identity與rendered observation三項成員已解除，但position-unknown與stopping交互仍未解除，且Round 1修正引入confirmed source wording矛盾；兩者均為blocking。

## Fix Actions

- Verified resolution removal：移除Round 1「一般stopping／clear pending／failed／success lifecycle矛盾」成員；Reviewer V確認position仍可信時各artifacts已一致。
- Verified resolution removal：移除Round 1「marker-only update重建route overlay」成員；Reviewer V確認design、spec與tasks均要求overlay identity同步及直接boundary test。
- Verified resolution removal：移除Round 1「rendered test只查identifier」成員；Reviewer V確認同一`NSHostingView`、同一annotation instance與coordinate assertion已明定。
- 修正 `proposal.md`、`design.md`、`specs/location-simulation/spec.md`、`tasks.md`：`.stopping` projection延續`routeSession.interruption?.positionKnowledge` gate，position unknown後stop／clear pending／clear failure不得重新顯示marker，並加入直接regression test。
- 修正同四份artifacts：marker來源contract改為「route已確認truth」，明確區分`.route`的snapshot confirmed coordinate與`.stopping`的同一route session confirmed coordinate。
- 重新執行 `.cash-skills/bin/cash validate show-confirmed-iphone-route-marker`：`Validation passed`。
- post-fix mechanical self-check：spec annotation count、separator lint與projection／positionKnowledge identifier cross-grep均通過。

## Decision

next_round
