# Cash Propose Review — Round 2

## Reviewer Findings

### Critical

無。

### Warning

1. `severity`: `Warning`
   `confidence`: `100`
   `layer`: `design`
   `location`: `design.md` Decision 3、Implementation Contract 9；`tasks.md` 1.3
   `summary`: 新 route 與尚未消耗的 preview intent 同輪出現時，原修正只讓 route 先套用，卻未消耗 preview intent；下一次 redraw 可能把 camera 從 route fit 拉回搜尋座標。
   `recommendation`: route fit 勝出時消耗但不執行同輪 preview identity，並以第二次無關 redraw 驗證 preview camera 不延遲重播。
   `disposition`: `fix-introduced`
   `introduced_by`: `propose-r1.md` Fix Actions「定義新 route fit 優先、已消耗 route identity 不遮蔽新搜尋 intent；要求 applyRoute 回傳本次是否套用」及 route precedence tests 修正。
   reviewer source：Reviewer V — Verification

### Suggestion

無。

## Rating

- cumulative blocking Critical：0
- cumulative blocking Warning：1
- non-blocking triaged findings：0
- `critical_gap`: `false`
- `round_type`: `micro`
- rationale：Reviewer V 明確確認 Round 1 的五個 cumulative members 均已解決並移出 blocking set，但 route precedence fix 引入一個 confidence 100、`fix-introduced` 的 Warning。該 finding 進入 cumulative blocking set；修正後仍需下一個 fresh Reviewer V 驗證，因此本輪為 `next_round`。

## Fix Actions

- verified resolution removal：Round 1「coordinate-based preview 去重」由 Reviewer V 以 `MapPreviewCameraIntent.identity: MapSearchGeneration`、spec scenario 與 task 1.3 確認 resolved，移出 cumulative blocking set。
- verified resolution removal：Round 1「`beginSearch(query:)` stale intent」由 Reviewer V 以 design contract 4 與 tasks 1.1、2.1 確認 resolved，移出 cumulative blocking set。
- verified resolution removal：Round 1「未測 orchestration transition」由 Reviewer V 以 `LocationMapModel` 單一 ownership及 model／canvas雙層 tests確認 resolved，移出 cumulative blocking set。
- verified resolution removal：Round 1「route overlay 遮蔽後續搜尋」由 Reviewer V 以 route-consumed precedence contract、scenario 與 task確認 resolved，移出 cumulative blocking set。
- verified resolution removal：Round 1「spy 未計數 `setCenter`」由 Reviewer V 以 design contract 及 tasks 1.2確認 resolved，移出 cumulative blocking set。
- 修改 `design.md`：新增 `LocationMapCameraEffects.consumePreview(_:)` contract；新 route fit 勝出時消耗同輪 preview identity但不執行 camera mutation，後續才產生的新搜尋 intent仍可置中。
- 修改 `specs/location-simulation/spec.md`：新增「新路線優先且搜尋 intent 不延遲重播」scenario。
- 修改 `tasks.md`：要求 route 與 preview 同輪只執行 route fit，並在第二次無關 redraw驗證 preview不延遲重播；實作 task明列 `consumePreview(_:)`。
- 修正後重新執行 `cash validate preserve-map-camera-on-click`，結果為 `Validation passed.`。
- 修正後機械 self-check 通過：delta annotation delimiters 平衡、MODIFIED title 與 master spec byte-for-byte 一致、`consumePreview` 與 route precedence 跨 artifacts 一致；所有 open signals 均無 `check` field。

## Decision

next_round
