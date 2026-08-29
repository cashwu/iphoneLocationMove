# Cash Apply Review — Round 1

## Reviewer Findings

Round 1 為 unseeded run 的第一輪，因此所有通過 confidence filter 的 Critical 與 Warning 皆為 blocking，且不需標註 `disposition`。

### Critical

（無）

### Warning

1. `severity`: Warning／`confidence`: 96／`layer`: test／來源：Reviewer A
   - `location`: `iPhoneLocationMoveTests/ContentViewTests.swift` 的 `favoritesList` 與 `assertSidebarLayout`
   - `summary`: 側欄回歸測試只要求「設定位置」按鈕與 sidebar bounds 有交集；按鈕即使只露出一小部分仍可能通過，零筆與大量收藏的 `minY` 相同也無法證明兩者完整可見。
   - `recommendation`: 對四種收藏數 fixture 的「設定位置」按鈕直接驗證完整垂直範圍位於 sidebar bounds 內，保留 1 點量測誤差。

### Suggestion

（無）

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 1
- 非 blocking triaged finding count: 0
- `critical_gap`: false
- `round_type`: full

rationale：Reviewer A 的 finding 有明確程式證據且 confidence 96，通過 filter 後成為 blocking Warning。Reviewer B 未回報 finding。cumulative blocking set 尚有一筆 Warning，故本輪不得通過。

## Fix Actions

- 在 `favoritesList` 取得 `sidebar-button-set-location` frame 後，針對零筆、三筆、六筆與二十筆收藏的每個 fixture，直接斷言按鈕 `minY` 與 `maxY` 完整位於 sidebar bounds 內，容許 1 點量測誤差。
- 初次嘗試把垂直 containment 套用到 `assertSidebarLayout` 的所有按鈕；完整測試指出部分既有狀態會刻意保留側欄捲動位置，搜尋按鈕可位於 viewport 外。隨即將 oracle 收斂到本 requirement 指定的「設定位置」按鈕，避免改變其他狀態測試語意。
- focused 側欄回歸測試通過；完整 macOS 測試套件 247 個測試、0 failure；Python protocol 測試 14 個通過。

本輪修復檔案：`iPhoneLocationMoveTests/ContentViewTests.swift`。

Touched-state 警告：`cash touched ensure` 與 `cash touched record` 均以 `error.code = touched_invalid` 失敗；既有 touched state 仍保存 task 1.5 修改前的完整描述，與目前 `tasks.md` 不一致，因此未能記錄本輪的 `iPhoneLocationMoveTests/ContentViewTests.swift`。依 workflow 規則此警告不改變 round decision，並帶入完成回覆。

## Decision

next_round
