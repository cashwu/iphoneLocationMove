# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

無。

### Warning

- severity: Warning
  confidence: 90
  layer: design
  location: `openspec/changes/fix-repeat-search-result-selection/design.md`「Decisions 3／Implementation Contract 5–6」、`openspec/changes/fix-repeat-search-result-selection/tasks.md` 2.3；實際 call site `iPhoneLocationMove/Features/Map/LocationMapView.swift:442`
  summary: artifacts 未規定先通過 model membership gate 再取消 async work；重繪前殘留的舊結果 action 可能先取消較新的 MapKit search 或 reverse-geocode，之後才被 model 拒絕。
  recommendation: 明定 model 成功取得 selection ownership 後才能取消 view-local async work，並加入 owner/view boundary regression case。
  reviewer source: Reviewer B — Quality

### Suggestion

無。

Reviewer A — Adherence 回報無 findings。

## Rating

- post-filter cumulative blocking Critical: 0
- post-filter cumulative blocking Warning: 1
- non-blocking triaged finding: 0
- critical_gap: false
- round_type: full
- rationale: Round 1 的 Warning 具有 90 confidence，直接指出 stale view action 可能破壞較新 async ownership，因此進入 cumulative blocking set。已補齊 side-effect ordering contract、scenario 與 regression task，仍需 fresh Reviewer V 驗證修正是否完整且未引入新缺陷。

## Fix Actions

- 修改 `openspec/changes/fix-repeat-search-result-selection/proposal.md`：補充 model validation 成功後才能取消 view-local async work。
- 修改 `openspec/changes/fix-repeat-search-result-selection/design.md`：定義 model-first ordering、stale action 無取消副作用與 owner/view boundary test contract。
- 修改 `openspec/changes/fix-repeat-search-result-selection/specs/location-simulation/spec.md`：新增「重繪前的舊結果 action 不取消較新搜尋」scenario。
- 修改 `openspec/changes/fix-repeat-search-result-selection/tasks.md`：要求 stale rendered action regression test，並把 task 2.3 的實作順序固定為 validate-before-cancel。
- 修正後機械式自檢通過：spec annotation 成對、無 stray separator、MODIFIED title 與 master spec byte-for-byte 相符、相關 identifier 與 side-effect ordering 敘述一致；所有 open signals 均無 `check` field 可執行。
- 修正後執行 `/Users/cash/Github/iphoneLocationMove/.cash-skills/bin/cash validate "fix-repeat-search-result-selection"`，結果為 `Validation passed.`。

## Decision

next_round
