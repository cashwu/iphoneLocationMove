# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

- `severity`: Critical
  `confidence`: 100
  `layer`: design
  `location`: `design.md`「Context／Decision 2／Implementation Contract 2」、`tasks.md` 3.2、`iPhoneLocationMove/ContentView.swift`
  `summary`: 現有 `ContentView` 未觀察 `DeviceSetupStore`，直接衍生 ready generation 不保證 map subtree 收到 state publication。
  `recommendation`: 由直接觀察 `DeviceSetupStore` 的 shell 組合 setup 與 map subtree，並以實際 store publication 測試 state transition。
  reviewer source: Reviewer A — Adherence、Reviewer B — Quality

### Warning

- `severity`: Warning
  `confidence`: 100
  `layer`: design
  `location`: `design.md`「Decisions 1–2／Implementation Contract 1」、`specs/mac-map-initial-location/spec.md`「重新連線建立新 generation」、`tasks.md` 1.1、1.3、2.1
  `summary`: 舊 generation 的 Core Location continuation 沒有 cancellation terminal path，斷線重連時可能拒絕新 generation 要求。
  `recommendation`: 以 cancellation-aware provider、per-request manager identity 與 serialized replacement 先完成舊 ownership，再啟動最新 generation。
  reviewer source: Reviewer A — Adherence、Reviewer B — Quality

- `severity`: Warning
  `confidence`: 100
  `layer`: design
  `location`: `design.md`「Decision 3／Implementation Contract 4–5」、`specs/mac-map-initial-location/spec.md`「初始置中不得覆寫使用者地圖脈絡」、`iPhoneLocationMove/Features/Map/LocationMapView.swift`
  `summary`: annotation-only 更新會走現有 route 分支並重播 `setVisibleMapRect`，仍可能奪回使用者 camera。
  `recommendation`: 為 preview、route 與 Mac initial center 定義可消耗的穩定 identity，只有新 identity 才執行 programmatic camera effect。
  reviewer source: Reviewer B — Quality

- `severity`: Warning
  `confidence`: 95
  `layer`: design
  `location`: `proposal.md`「Proposed Solution」、`design.md`「Goals／Decisions 1–2」、`specs/mac-map-initial-location/spec.md`「新 ready session 觸發一次定位」
  `summary`: per-generation request ledger 若由 `LocationMapView`／`LocationMapModel` 持有，重開主視窗會對同一 generation 重複要求。
  `recommendation`: 將 ledger 與 cached result 移到 `AppDelegate` 持有的 app-lifetime coordinator，並測試同 generation 重開視窗。
  reviewer source: Reviewer B — Quality

### Suggestion

None.

## Rating

- cumulative blocking Critical: 1
- cumulative blocking Warning: 3
- non-blocking triaged findings: 0
- `critical_gap`: true
- `round_type`: full
- rationale: 第一輪四項高信心 design findings 全部進入 cumulative blocking set；完成同步修正後仍需由新 reviewer 驗證，因此本輪為 `next_round`。

## Fix Actions

- 修改 `openspec/changes/show-mac-location-on-device-ready/proposal.md`：改由 app-lifetime coordinator 擁有 generation request，加入 replacement cancellation 與一次性 camera identity。
- 修改 `openspec/changes/show-mac-location-on-device-ready/design.md`：新增 `LocationWorkspaceView` observation boundary、`MacLocationCoordinator` app-lifetime ledger、per-request manager identity、cancellation terminal path、serialized replacement 與 route camera identity contract。
- 修改 `openspec/changes/show-mac-location-on-device-ready/specs/mac-map-initial-location/spec.md`：新增 pending request replacement、同 generation 重開視窗去重，以及 route 存在時 annotation update 不重播 camera effect 的 scenarios。
- 修改 `openspec/changes/show-mac-location-on-device-ready/tasks.md`：補齊 cancellation／late callback、真實 store publication、視窗重建與 route camera replay 的 deterministic tests 及 implementation delivery tasks。
- 修正後重新執行 annotation lint、identifier cross-grep、signal check 掃描與 `cash validate`；未發現額外機械缺陷，validation passed。

## Decision

next_round
