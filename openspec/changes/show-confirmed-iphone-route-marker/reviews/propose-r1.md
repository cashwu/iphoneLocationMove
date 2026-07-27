# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

- severity: Critical
  confidence: 100
  layer: design
  location: `design.md` Decisions 1–2、Implementation Contract 6；`specs/location-simulation/spec.md`「位置不確定或 clear 成功時移除 marker」；`tasks.md` 1.2、2.1
  summary: artifacts 錯誤假設 active route 進入 position-unknown interruption 後 `routeSnapshot` 會是 `nil`，但現有 `SimulationStore` 仍發布保留 `confirmedCoordinate` 的 `.route` snapshot，純投影會繼續顯示不可信 marker。
  recommendation: projection 必須依 route phase 與 `positionKnowledge` 過濾，並直接測試已有 confirmed coordinate 的 route 經 `handleDeviceInterruption(positionKnowledge: .unknown)` 後移除 marker。
  reviewers: Reviewer A、Reviewer B

### Warning

- severity: Warning
  confidence: 98
  layer: design
  location: `proposal.md` Proposed Solution；`design.md` Decisions 2、Implementation Contract 5–6；delta spec lifecycle scenarios；`tasks.md` 1.2、1.3
  summary: stop lifecycle 自相矛盾；proposal 承諾 clear 成功後才移除，但其他 artifacts 要求一進 `.stopping` 就移除，會在 clear pending／failed 且裝置仍持有模擬位置時隱藏 marker。
  recommendation: stopping、clear pending與clear failure保留最後 confirmed marker，僅 clear success、position unknown或 ownership replacement後移除，並測試 pending／failed clear。
  reviewers: Reviewer B

- severity: Warning
  confidence: 96
  layer: design
  location: `design.md` Decisions 3–4、Risks；`tasks.md` 1.1、2.2
  summary: marker 每秒觸發 canvas update時，現有無條件 `removeOverlays` 仍會每秒重建 route polyline，違反 marker-only sync 的無閃爍承諾。
  recommendation: 以 route identity／polyline equality同步 overlay，並在同一Coordinator boundary驗證 marker更新前後polyline identity與count不變。
  reviewers: Reviewer A、Reviewer B

- severity: Warning
  confidence: 90
  layer: design
  location: `design.md` Decision 5、Implementation Contract 8；`tasks.md` 1.2
  summary: 只搜尋穩定 accessibility identifier無法證明同一 rendered hierarchy因publisher而更新 annotation coordinate，可能讓 observation regression 在測試全綠時存在。
  recommendation: 在同一 `NSHostingView` 內同時驗證穩定identifier、同一annotation instance的coordinate更新與移除，不得重建root view或只讀store property。
  reviewers: Reviewer B

### Suggestion

- severity: Suggestion
  confidence: 85
  layer: design
  location: `design.md` Decisions 4–5；`tasks.md` 1.1
  summary: camera isolation測試若只獨立呼叫 `LocationMapCameraEffects`，無法證明marker的實際Coordinator update沒有誤觸其他camera operation。
  recommendation: 由同一Coordinator同步boundary連續提交marker coordinates，以spy驗證所有programmatic camera operation零增量且manual callback不變。
  reviewers: Reviewer B

## Rating

- Critical: 1
- Warning: 3
- Non-blocking triaged findings: 1
- critical_gap: true
- round_type: full
- rationale: unseeded first round的Critical與Warnings均為blocking；它們直接影響position-unknown truth semantics、clear ownership呈現、route overlay穩定性與observation regression test有效性，因此修正後必須進入micro verification。

## Fix Actions

- 修正 `proposal.md`、`design.md`、`specs/location-simulation/spec.md`、`tasks.md`：新增 `SimulationStore.confirmedRouteMarkerCoordinate` presentation projection，明確依route phase與`positionKnowledge`隱藏不可信marker，並加入既有confirmed route的position-unknown regression test。
- 修正同四份artifacts：統一stop lifecycle為clear pending／clear failure保留最後confirmed marker，clear success轉idle後才移除；將 `iPhoneLocationMove/Features/Simulation/SimulationStore.swift` 與 `iPhoneLocationMoveTests/SimulationStoreTests.swift` 加入structured scope。
- 修正 `proposal.md`、`design.md`、delta spec與`tasks.md`：要求route identity／polyline equality overlay sync，marker-only update保留同一polyline identity。
- 修正 `design.md` 與 `tasks.md`：rendered test必須在同一`NSHostingView`驗證穩定identifier及同一annotation instance coordinate更新／移除。
- 採納Suggestion並強化 `design.md`、`tasks.md`：camera test由同一Coordinator同步boundary注入spy，驗證route／preview／Mac operations零增量及manual callback不變。
- 重新執行 `.cash-skills/bin/cash validate show-confirmed-iphone-route-marker`：`Validation passed`。
- post-fix mechanical self-check：spec annotation count、separator lint、identifier cross-grep與scope path同步均通過；沒有signal `check` command需要執行。

## Decision

next_round
