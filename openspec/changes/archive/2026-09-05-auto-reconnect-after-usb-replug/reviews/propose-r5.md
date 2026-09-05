# Cash Propose Review — Round 5

## Reviewer Findings

### Cumulative blocking set 判定（Reviewer V）

- Warning（r4）「`SimulationLifecycleControlling` extension 位置與 `userActionTask` 可見性」：**resolved**。證據：design Decision 3、Contract 5／9、proposal Impact 與 Proposed Solution 3、tasks 2.4 delivery 均已加入 `AppLifecycleCoordinator.swift` 並敘述搬移；程式碼對照：該檔移除 119-134 行 extension 後無其他 `SimulationStore` 引用可獨立編譯，`AppLifecycleTests` 使用自有 fake 不依賴 extension 位置。verified-resolution removal：fix reference r4「Warning（AppLifecycleCoordinator.swift 未列入）」，verifying reviewer Reviewer V。

### Critical

（無）

### Warning

（post-filter 無 blocking Warning）

### Suggestion（非 blocking）

- severity: Suggestion（自 Warning 75 降級）；confidence: 75；layer: design；location: design.md Decision 2 seam 清單、Contract 7、tasks.md 2.2 的 AppShellTests 案例；summary: `AppShellDevice.setLocation` 永不拋錯且 design 只給它預設拋錯的 `reconnect()`，setup state oracle 案例無法觸發並完成 auto reconnect；recommendation: 為 `AppShellDevice` 增列 `failNextSet(_:)` 與 reconnect 結果佇列；reviewer source: Reviewer V Finding 1；disposition: `fix-introduced`；introduced_by: r4 Fix Action「Suggestion（deviceNotFound 與 setup state oracle）」
- severity: Suggestion；confidence: 50；layer: design；location: design.md Decision 3 `runUserAction` 與 `stopForQuit`；summary: 以 `defer` 在 `runUserAction` continuation 清空 `userActionTask`，`stopForQuit` 的 `while let` 迴圈終止依賴 MainActor 排程順序，可能空轉；recommendation: 清空動作放進 outer task 完成前；reviewer source: Reviewer V Finding 2；disposition: `fix-introduced`；introduced_by: r4 Fix Action「Suggestion／已過濾（single-flight 機制、指派時機、迴圈等待）」

### 已過濾（confidence < 50，僅記錄）

- （40）Contract 5 未如 D6 與 tasks 2.4 提及 `*.start_failed`／`stop_failed` 只記 case 名稱。
- （35）`hasActiveSimulation` 含 `userActionTask` 後普通 stop 進行中退出亦先確認；與既有語意一致。

### Fix propagation 檢查

r4 十二項修正概念全部通過（capture lease、`userActionTask`＋`runUserAction`、`stopForQuit` 迴圈、replacement 起點、`deviceNotFound`、start current 判準、clear 失敗順序、睡眠解讀註記、`*.start_failed` case 名稱、2.1 success、Impact＝delivery、`[P]`）；AppShellTests oracle 文件一致但 seam 不足（Finding 1）。

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 0
- non-blocking triaged finding count: 2
- critical_gap: false
- round_type: micro
- rationale: 唯一 member 已 verified-resolution 移除，新 finding 經信心過濾皆非 blocking，pass condition 成立。但 Finding 1 會讓 apply 階段的 tasks 2.2 需要 design 未定義的 seam（觸發 test-task-requires-missing-seam），主 agent 選擇修正並以第六輪 micro 驗證，確保交付給 apply 的 design 完整。

## Fix Actions

- **Suggestion（AppShellDevice seam）**：design.md Decision 2 seam 清單增列 `AppShellDevice` 的 `failNextSet(_:)` 與 `enqueueReconnectResult(_:)`；tasks.md 2.1 的 AppShellDevice 敘述與 2.2 的 AppShellTests 案例同步。
- **Suggestion（`userActionTask` 清空時機）**：design.md Decision 3 改為清空動作放在 outer task 於完成前同步執行，`stopForQuit` 迴圈不依賴排程順序；Contract 5、tasks.md 2.4 同步。
- 修正後重新執行 `validate`：通過。修正後機械自檢：`enqueueReconnectResult`／`failNextSet` 在 design 與 tasks 一致；七個 MODIFIED 標題逐字存在於 master；Impact 與 tasks delivery 集合未改變。
- 修改檔案（2）：design.md、tasks.md。change 目錄外無修改，不呼叫 touched record。

## Decision

next_round
