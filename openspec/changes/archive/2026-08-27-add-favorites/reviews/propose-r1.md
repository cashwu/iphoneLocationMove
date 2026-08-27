# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

- severity: Critical；confidence: 90；layer: design；location: design.md「Context」＋ Decision 9；tasks.md 1.1／2.1／3.2；summary: design 宣稱「專案為手動維護的 `project.pbxproj`（無 XcodeGen）」不成立——`iPhoneLocationMove/project.yml` 存在且 README 明定以 xcodegen generate 重新產生專案，targets 以目錄掃描收檔；recommendation: 改寫 Context 與 Decision 9 為 XcodeGen regen 工作流，調整 tasks 的註冊與 diff 驗收判準；reviewer: A（主 agent 已親自核實 `iPhoneLocationMove/project.yml` 與 README.md 第 124-131 行）

### Warning

- severity: Warning；confidence: 85；layer: design；location: tasks.md 1.2；design.md Implementation Contract（`selectFavorite`）；summary: 「generation 耗盡丟出 identityExhausted」的 model-level 測試無現有 seam 可寫（`mapSearchGeneration` 為 `@Published private(set)` 且無 seed 注入），codebase 慣例是型別層直接測（`DeviceLocationClientTests.swift` 對 `DeviceSessionGeneration(rawValue: .max)` 斷言）；recommendation: 改為 `MapSearchGeneration(rawValue: .max).advanced()` 型別層斷言，不引入未定義的 seed seam；reviewer: A

### Suggestion（post-filter 降級與原生 Suggestion）

- severity: Suggestion（原 Critical，confidence 78 → [50,80) 降級）；confidence: 78；layer: design；location: design.md Decisions 6、Risks；proposal.md Alternatives；summary: App 支援多主視窗（`WindowGroup` + ⌘0 `openWindow`），兩個 `LocationMapView` 各自 `@StateObject` 持有 `FavoritesStore` 會 last-writer-wins 覆寫同一 key，收藏靜默遺失且 UI 不跨視窗同步；recommendation: 改由 `AppDelegate` 持有單一實例注入（比照 `riskNoticeStore`）；reviewer: B（主 agent 已親自核實 `iPhoneLocationMoveApp.swift:276,435` 的多視窗證據——finding 屬實，雖經 confidence filter 降為非阻塞仍本輪修正）
- severity: Suggestion（原 Warning 75 降級）；confidence: 75；layer: text；location: tasks.md 1.1；spec Example「無地址時的預設名稱」；summary: 預設名稱規則（地址快照／nil 時 5 位小數座標文字）無任何 task 驗收，且「取小數 5 位」的捨入語義二義；recommendation: task 1.1 明列預設名稱案例含 Example 精確字串，design 明定四捨五入；reviewer: A＋B（同一 finding 聚合）
- severity: Suggestion（原 Warning 75/65 降級）；confidence: 75；layer: text；location: tasks.md 1.3；spec「我的最愛清單」rename scenarios；summary: rename 的行內編輯 UI 契約只有 store 層測試，無 view 層 rendered-hierarchy 案例（對應 open signal `spec-scenario-no-view-test-task`）；recommendation: task 1.3 增 rename 提交後同 hierarchy 顯示新名稱、空白提交回顯原名的案例；reviewer: A＋B（聚合）
- severity: Suggestion（原 Warning 70 降級）；confidence: 70；layer: design；location: design.md Decision 2；proposal Proposed Solution 1；summary: 「單筆壞資料不丟棄整份清單」承諾與「整體 decode 失敗歸零」機制不一致，欄位毀損會使整個陣列 decode 失敗並在下次寫入時銷毀全部收藏；recommendation: 改逐元素 lossy decode，歸零僅限整份非清單結構並記為刻意取捨；reviewer: B
- severity: Suggestion（原 Warning 70 降級）；confidence: 70；layer: design；location: design.md Decision 7；summary: rename 行內編輯與列點選共存的互動衝突（編輯中點選、Esc、失焦語義）未定義；recommendation: 編輯模式停用該列點選、submit 唯一提交路徑、Esc／失焦丟棄；reviewer: B
- severity: Suggestion（原 Warning 60 降級）；confidence: 60；layer: design；location: design.md Implementation Contract「寫入失敗不 crash」；summary: 契約 API 面上「寫入失敗」不可表示（JSONEncoder 對該 DTO 不失敗、`UserDefaults.set` 不 throw），對應測試案例無法落 red；recommendation: 改為可驗證形式（無 `try!`／`fatalError`、寫入結果不影響記憶體狀態）並以寫入丟棄型 UserDefaults 子類驗證；reviewer: B
- severity: Suggestion；confidence: 55；layer: design；location: design.md Implementation Contract「恆依 addedAt 遞增排序」；summary: `addedAt` 相等時順序未定義且 Swift sort 非穩定，違反「順序不變」scenario 的極端情形；recommendation: 改為 append 順序即事實來源、不重排；reviewer: B
- severity: Suggestion；confidence: 60；layer: design；location: design.md Decision 4；summary: 無地址收藏選用後永不補查地址的快照語義未言明；recommendation: 在 Risks 明記為刻意取捨；reviewer: B
- severity: Suggestion；confidence: 55；layer: text；location: tasks.md 2.3；summary: 「依 addedAt 排序」措辭暗示 view 端重複排序，屬重複既有 invariant 的複雜度邀請；recommendation: 改為依 `favorites` 既有順序渲染；reviewer: B
- severity: Suggestion；confidence: 55；layer: text；location: spec「取消最愛不影響當前 preview」↔ tasks 1.3；summary: scenario 的「模擬不中斷」無對應斷言；recommendation: task 1.3 佈置模擬目標並斷言模擬狀態不變；reviewer: A

## Rating

- post-filter cumulative blocking set：Critical 1（XcodeGen 事實錯誤）、Warning 1（identityExhausted 測試 seam）
- non-blocking triaged finding count: 10
- critical_gap: true
- round_type: full
- 理由：run 首輪，全部 surviving Critical／Warning 皆為阻塞。Reviewer A 的 XcodeGen finding 經主 agent 親自核實成立，直接影響三個 task 的註冊機制與驗收判準；Reviewer A 的測試 seam finding 亦核實（`mapSearchGeneration` 無 seed 注入、型別層測試為既有慣例）。兩者皆需修正後由下一輪驗證，故 decision 為 next_round。

## Fix Actions

依「address every surviving finding」義務，本輪修正全部 12 個 finding（含 10 個非阻塞者）：

1. （阻塞 Critical）design.md Context 與 Decision 9 改寫為 XcodeGen regen 工作流（目錄掃描、`project.yml` 不需修改、regen diff 檢查納入 `xcodegen-regeneration-scope-drift`／`generated-user-state-scope-drift` 防線）；tasks 1.1／2.1 的註冊描述改為 regen、task 3.2 的 success 改為「新檔 registration 與 regen 正規化」且明定 `iPhoneLocationMove/project.yml` 不得有 diff。修改檔案：design.md、tasks.md。
2. （阻塞 Warning）tasks 1.2 的 exhaustion 案例改為型別層斷言 `MapSearchGeneration(rawValue: .max).advanced()`；design.md Contract 註明 exhaustion 由型別層契約保證。修改檔案：tasks.md、design.md。
3. （非阻塞，B1 多視窗）ownership 改為 `AppDelegate` 單一實例：design Decisions 1／6、Implementation Contract（新增 AppDelegate 與 ContentView／LocationWorkspaceView 段落、`@ObservedObject` 必要參數）、Risks 移除「view 持有 store」段；proposal Proposed Solution 1 與 Alternatives 對調取捨方向；proposal Impact 新增 iPhoneLocationMove/App/iPhoneLocationMoveApp.swift 與 iPhoneLocationMove/ContentView.swift；tasks 2.3 delivery 同步。修改檔案：design.md、proposal.md、tasks.md。
4. （非阻塞）預設名稱驗收：tasks 1.1 明列地址快照與「25.03396, 121.56447」案例；design Decision 3 明定四捨五入（等同 String(format: "%.5f")）。修改檔案：tasks.md、design.md。
5. （非阻塞）rename view 測試：tasks 1.3 增同 hierarchy rename 提交／空白回顯案例。修改檔案：tasks.md。
6. （非阻塞）lossy decode：design Decision 2 改逐元素 lossy decode；spec「最愛清單持久化與載入驗證」requirement 措辭同步（「單筆無法解碼或座標驗證失敗…整份資料非合法清單結構」）；proposal Proposed Solution 1 同步；tasks 1.1 增欄位毀損跳過案例；Risks 記「DTO 無版本欄位」為刻意取捨。修改檔案：design.md、specs/favorite-places/spec.md、proposal.md、tasks.md。
7. （非阻塞）rename 互動語義：design Decision 7 補編輯模式停用點選、submit 唯一提交、Esc／失焦丟棄；tasks 2.3 同步。修改檔案：design.md、tasks.md。
8. （非阻塞）寫入失敗契約：design Contract 改為可驗證形式；tasks 1.1 改以寫入丟棄型 UserDefaults 子類驗證。修改檔案：design.md、tasks.md。
9. （非阻塞）順序語義：design Contract 改為 append 順序即事實來源、不重排；Goals 措辭同步；tasks 1.1 改為 append 順序保持案例；tasks 2.3 改為依既有順序渲染（同時解決 view 重複排序 finding）。修改檔案：design.md、tasks.md。
10. （非阻塞）地址快照語義：design Risks 增「地址快照語義」段。修改檔案：design.md。
11. （非阻塞）模擬不中斷斷言：tasks 1.3 該案例補 SimulationStore 佈置與模擬狀態不變斷言。修改檔案：tasks.md。

修正後已重跑 pre-round mechanical self-check（annotation lint 0/0、stale identifier 掃描僅剩 proposal Alternatives 中被否決方案的刻意 `@StateObject` 引述、新 identifier `@ObservedObject`／`LocationWorkspaceView`／lossy／xcodegen 跨 artifact 一致）並重跑 `"$cash_cli" validate "add-favorites"`：Validation passed。

主 agent 對 B1（多視窗）之核實紀錄：`iPhoneLocationMoveApp.swift` line 276 `WindowGroup(id: AppWindow.mainID)`、line 435 `openWindow(id: AppWindow.mainID)`（⌘0）屬實；finding 為真實 design 缺陷，惟依 confidence filter（78 < 80）機械降為非阻塞 Suggestion，本輪已一併修正，非以升級阻塞方式處理。

## Decision

next_round

阻塞集合（Critical 1、Warning 1）於本輪發現並已記錄修正，需由下一輪（micro，Reviewer V）驗證解決與 fix propagation；依 graded convergence 規則第二輪為 micro round。
