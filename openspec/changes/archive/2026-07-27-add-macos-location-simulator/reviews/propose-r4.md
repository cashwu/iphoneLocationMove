# Cash Propose Review — Round 4

## Reviewer Findings

### Critical

None.

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`disposition`: unresolved-prior；`location`: `design.md` MapKit async request identity、`specs/location-simulation/spec.md`「地圖搜尋、選點與明確確認」、`tasks.md` 4.1；`summary`: `MapSearchGeneration` 只由新 query 失效，search in flight 時直接點擊地圖仍可能被舊 response 覆寫；`recommendation`: 所有 preview ownership change 都遞增 generation，加入 search → map click race test；reviewer source：Reviewer B — Quality。
2. `severity`: Warning；`confidence`: 95；`layer`: design；`disposition`: new；`location`: `design.md` lifecycle／reconnect、`specs/ios-device-session/spec.md` cleanup、`tasks.md`；`summary`: App crash 或 clear failure 後強制退出可能留下未知裝置座標，relaunch 沒有持久 cleanup-pending UDID；`recommendation`: 第一次 mutation 前持久記錄最小 cleanup ownership，confirmed clear 後移除，relaunch 先恢復 clear；reviewer source：Reviewer B — Quality。
3. `severity`: Warning；`confidence`: 100；`layer`: design；`disposition`: fix-introduced；`introduced_by`: `propose-r1.md` `## Fix Actions` 中修改 `tasks.md` 加入 device-switch acceptance；`location`: `tasks.md` 7.4、`specs/ios-device-session/spec.md` device switch；`summary`: 一台 iPhone 的 physical acceptance 無法執行需要第二台裝置的 active-device switch failure；`recommendation`: 改為兩裝置 acceptance，或明確由 fake-boundary integration test 承擔；reviewer source：Reviewer B — Quality；原始 reviewer tag 為 `new`。

### Suggestion

None.

## Rating

- post-filter cumulative blocking Critical: 0
- post-filter cumulative blocking Warning: 2
- non-blocking triaged finding: 1
- `critical_gap`: false
- `round_type`: full
- 理由：兩位 checkpoint reviewers 都驗證移除 W5；W10 以同一 stale-response mechanism 重新出現而成為 `unresolved-prior`。主 agent disposition 稽核另將單裝置 acceptance finding 從 `new` 更正為 `fix-introduced`，因此兩項進入 cumulative blocking set。cleanup ownership persistence 是 surviving `new`，依規則列為 non-blocking triage。

## Fix Actions

- verified resolution removal：W5 route update backpressure／pause physical-coordinate barrier；Reviewer A 與 Reviewer B 都確認手動 pause、sleep pause、實體 correction、uncertain failure 與 tasks 已一致。
- 修改 `design.md`：明定新 query、直接點擊地圖、清除搜尋或其他 preview source replacement 都遞增 `MapSearchGeneration` 並取消／忽略舊 search。
- 修改 `specs/location-simulation/spec.md`：直接點擊地圖先失效 in-flight search，新增 map click 後舊 response 晚到仍保留手動座標 scenario。
- 修改 `tasks.md` 4.1：加入 search in flight → map click → old response 與清除搜尋後 stale response tests。
- disposition correction：physical acceptance finding 原始 `new` 更正為 `fix-introduced`；證據是 `propose-r1.md` Fix Actions 將 active-device switch failure 加入原本限定一台 iPhone 的 task 7.4。
- 修改 `tasks.md` 7.4：移除單裝置環境無法執行的 physical switch acceptance，明確由 task 3.2 fake-boundary integration test 驗證 transaction。
- non-blocking triage：App crash／force-quit 後持久 cleanup ownership 為 `new` Warning；本輪不擴張 fix，將在 signals write step 建立 recurring-finding signal，完成摘要須醒目列出。
- 修正後機械自檢通過：annotation 均為 `0/0`、無 stray separator、18 個 requirements／68 個 scenarios／2 個 examples／24 個 tasks 的來源計數已重算、MapSearchGeneration／preview ownership／single-device acceptance 跨 artifacts 一致、沒有 MODIFIED／REMOVED title identity 或 open signal check。
- 修正後 `cash validate add-macos-location-simulator` 通過。

## Decision

next_round
