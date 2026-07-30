# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

無。

### Warning

1. `severity`: `Warning`
   `confidence`: `100`
   `layer`: `design`
   `location`: `design.md` Decisions 2、Risks / Trade-offs；`iPhoneLocationMove/Features/Map/LocationMapView.swift:1350-1364`
   `summary`: coordinate-based preview 去重會讓「搜尋 A → 直接點擊 B → 再搜尋 A」的第二次搜尋置中被錯誤抑制。
   `recommendation`: 以每次搜尋 selection 的 identity 去重，並新增返回相同 coordinate 的 boundary test。
   reviewer source：Reviewer B — Quality

2. `severity`: `Warning`
   `confidence`: `100`
   `layer`: `design`
   `location`: `design.md` Decisions 1、Implementation Contract 4；`tasks.md` 2.1；`iPhoneLocationMove/Features/Map/LocationMapModel.swift:278-293`
   `summary`: `beginSearch(query:)` 會清空 preview，但原設計未同步清除 camera target，可能留下與 render state 脫鉤的 stale intent。
   `recommendation`: 明列並測試 `beginSearch`、`clearSearch`、Reset 與其他 preview mutation 的 intent transition。
   reviewer source：Reviewer B — Quality

3. `severity`: `Warning`
   `confidence`: `100`
   `layer`: `design`
   `location`: `design.md` Decisions 1、Implementation Contract 2–4、9；`tasks.md` Regression Tests 1.1–1.2
   `summary`: 原測試只向 Coordinator 注入 target，未驗證真正決定搜尋／點擊分類與 clear 行為的 orchestration seam。
   `recommendation`: 將 intent transition 放入可直接測試的 owner，覆蓋搜尋成功、點擊成功、validation failure 與所有 preview-clear path，再保留 canvas boundary test。
   reviewer source：Reviewer A — Adherence、Reviewer B — Quality

4. `severity`: `Warning`
   `confidence`: `100`
   `layer`: `design`
   `location`: `design.md` Goals、Implementation Contract 7；`proposal.md` Proposed Solution；`iPhoneLocationMove/Features/Map/LocationMapView.swift:1626-1644`
   `summary`: route overlay 存在時原 Coordinator 永遠停在 route 分支，即使 route identity 已消耗，也會遮蔽新的搜尋 preview center。
   `recommendation`: 定義新 route fit 與搜尋 intent 的 precedence，並測試已消耗 route identity 不遮蔽後續搜尋置中。
   reviewer source：Reviewer A — Adherence

5. `severity`: `Warning`
   `confidence`: `100`
   `layer`: `design`
   `location`: `design.md` Implementation Contract 6、9；`tasks.md` Regression Tests 1.1–1.2；`iPhoneLocationMoveTests/LocationMapModelTests.swift:1048-1093`
   `summary`: `CameraOperationSpyMapView` 原本只計數 `setRegion` 與 `setVisibleMapRect`，無法證明 contract 禁止的 `setCenter` 未被呼叫。
   `recommendation`: 擴充 spy 計數 `setCenter(_:animated:)`，對直接點擊、地址 redraw 與連續選點明確斷言所有 camera mutation 零增量。
   reviewer source：Reviewer A — Adherence

### Suggestion

無。

## Rating

- cumulative blocking Critical：0
- cumulative blocking Warning：5
- non-blocking triaged findings：0
- `critical_gap`: `false`
- `round_type`: `full`
- rationale：第一輪有五個 confidence ≥ 80 的 Warning，依 unseeded first-round 規則全部進入 cumulative blocking set。雖已完成 artifact 修正，仍需 fresh Reviewer V 驗證修正有效且未引入新缺陷，因此本輪為 `next_round`。

## Fix Actions

- 修改 `proposal.md`：將 `LocationMapModel` 納入 affected code，並改為由既有 model owner 持有帶 `MapSearchGeneration` 的 preview camera intent。
- 修改 `design.md`：以 `MapPreviewCameraIntent` 與既有 `MapSearchGeneration` 取代 coordinate-based target 去重；完整定義搜尋、直接點擊、`beginSearch`、`clearSearch`、reverse geocode、Reset 與 validation failure transitions。
- 修改 `design.md`：定義新 route fit 優先、已消耗 route identity 不遮蔽新搜尋 intent；要求 `applyRoute` 回傳本次是否套用。
- 修改 `specs/location-simulation/spec.md`：新增「回到相同搜尋座標仍重新置中」與「既有路線不遮蔽後續搜尋置中」scenarios。
- 修改 `tasks.md`：加入 model transition tests、相同 coordinate 的新 identity test、route precedence tests，並要求 spy 計數 `setRegion`、`setCenter`、`setVisibleMapRect`。
- 修正後重新執行 `cash validate preserve-map-camera-on-click`，結果為 `Validation passed.`。
- 修正後機械 self-check 通過：delta annotation delimiters 平衡、MODIFIED title 與 master spec byte-for-byte 一致、`previewCameraTarget` stale identifier 為零、跨 artifacts 識別字一致；所有 open signals 均無 `check` field。

## Decision

next_round
