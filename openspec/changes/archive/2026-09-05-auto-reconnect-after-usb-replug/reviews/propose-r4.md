# Cash Propose Review — Round 4

## Reviewer Findings

### Cumulative blocking set 判定（checkpoint full round，Reviewer A 與 Reviewer B）

- Warning（r3）「MODIFIED『工作區重置』漏抄『重置後的鏡頭行為』scenario」：Reviewer A **resolved**（程式擷取 master 605-680 行 diff，7 scenario／1 Example 逐字存在，差異僅兩處 `reconnecting`）；Reviewer B **resolved**（同法，差異僅兩處 busy 枚舉與 master-only 的 @trace）。verified-resolution removal：fix reference r3「Warning（漏抄 scenario）」，verifying reviewers Reviewer A 與 Reviewer B。

### Critical

（無）

### Warning

- severity: Warning；confidence: 85；layer: design；location: design.md Implementation Contract 5／9、proposal.md Impact、tasks.md 2.4 delivery；對照 `iPhoneLocationMove/App/AppLifecycleCoordinator.swift` 119-134 行；summary: `hasActiveSimulation` 與 `stopForQuit()` 實際定義在 `AppLifecycleCoordinator.swift` 的 `extension SimulationStore: SimulationLifecycleControlling`，design 卻歸給 `SimulationStore.swift` 並宣稱 `AppLifecycleCoordinator` 不變，且 `userActionTask` 為 `private` 無法被跨檔 extension 讀取；Impact 與 tasks 都未列該檔；recommendation: 把 extension 搬到 `SimulationStore.swift`，Impact／tasks 2.4 加入該檔，Contract 9 改寫；reviewer source: Reviewer A Finding 1；disposition: `fix-introduced`；introduced_by: r1 Fix Action「Suggestion（single-flight／quit）」

### Suggestion（非 blocking）

- severity: Suggestion；confidence: 60；layer: text；location: design.md Decision 1；summary: `markUSBDisconnected` 把 `tunnelLease` 清為 nil 後，`handleUSBDisconnect` 既有的非同步 `stopTunnel` 讀不到 lease；recommendation: mark 前 capture；reviewer source: Reviewer B Finding 1；disposition: `new`
- severity: Suggestion；confidence: 55；layer: design；location: design.md Decision 3、Contract 5；summary: `userActionTask` 與 `commandInProgress` 重複，且三個入口由 caller 直接 await、`startRoute` 會 throw，`Task<Void, Never>` 包裝方式未明定；recommendation: 單一真相與 `runUserAction` helper；reviewer source: Reviewer B Finding 2；disposition: `fix-introduced`；introduced_by: r1 Fix Action「Suggestion（single-flight／quit）」
- severity: Suggestion；confidence: 55；layer: design；location: specs/location-simulation「已中斷的舊 session 被新模式取代」 vs tasks.md；summary: 該 scenario 無從 interrupted 舊 session 起始的測試；recommendation: 2.2 增列；reviewer source: Reviewer A Finding 2 與 Reviewer B Finding 5(b) 合併；disposition: `new`
- severity: Suggestion；confidence: 55；layer: design；location: tasks.md 2.2 vs spec「reconnect 失敗」「上層經由 client seam」；summary: `deviceNotFound` 映射與「setup ready generation 不變、不重新要求 Mac 位置」無測試；recommendation: 2.2 增列 `deviceNotFound` 與 AppShellTests 斷言；reviewer source: Reviewer B Finding 5(a)(c) 與 Reviewer A Finding 3（45，標 `unresolved-prior`，主 agent 校正：對應的 r1 finding 為非 blocking Suggestion，依規則維持 `new`）合併；disposition: `new`
- severity: Suggestion；confidence: 50；layer: text；location: design.md Decision 3 第一點；summary: start 路徑「仍為 current」缺可執行判準（此時 `activeSessionID` 為 nil）；recommendation: 以 `state` 仍為 `reconnecting(_, sessionID)` 判定；reviewer source: Reviewer B Finding 3；disposition: `new`
- severity: Suggestion；confidence: 50；layer: design；location: design.md Decision 2 非 `usbDisconnected` 分支順序；summary: 先 await 再清 session，兩個 await 之間重入的 clear 會得到 `staleGeneration`；未說明 `try` 或 `try?`；recommendation: 同步清除後再以 `try?` 非同步拆除；reviewer source: Reviewer B Finding 4；disposition: `fix-introduced`；introduced_by: r2 Fix Action「fix-introduced（reconnect 內再次拔線）」

### 已過濾（confidence < 50，僅記錄）

- Reviewer A Finding 4（40）：master「系統睡眠與裝置中斷不造成位置跳躍」的「tunnel death」泛稱與停止動作 clear 的張力。
- Reviewer A Finding 5（35）：`userActionTask` 指派時機未明（與 Reviewer B Finding 2 同類）。
- Reviewer B Finding 6（45）：`stopForQuit` 單次 await 後仍可能被新 start 插入。
- Reviewer B Finding 7（45）：1.1 與 2.1 平行時 2.1 的 success「既有案例零失敗」與 1.1 紅燈矛盾。
- Reviewer B Finding 8（40）：reconnect 失敗來源的既有 `*.start_failed`／`stop_failed` 事件仍以 `String(describing:)` 記完整 failure。

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 1
- non-blocking triaged finding count: 6
- critical_gap: false
- round_type: full
- rationale: 先前唯一的 member 由兩位 reviewer 一致判定 resolved 並移除；本輪 Reviewer A 回報一個 confidence 85 的 `fix-introduced` Warning（delivery 路徑與程式碼位置不符、`private` 可見性使 design 無法落實），進入 cumulative blocking set，必須修正並由下一輪驗證。其餘為非 blocking 機制細節，一併修正。

## Fix Actions

- **Warning（AppLifecycleCoordinator.swift 未列入）**：採方案 (a)：design.md Decision 3 註明把 `SimulationLifecycleControlling` 的 `SimulationStore` extension 搬到 `SimulationStore.swift`、`userActionTask` 為 `private(set)`；Implementation Contract 5 delivery 加入 `AppLifecycleCoordinator.swift`、Contract 9 改為「class 與 protocol 不變，唯一改動是移除該 extension」；proposal.md Impact Modified 與 Proposed Solution 第 3 點加入該檔；tasks.md 2.4 delivery 加入該檔、regression 加入 `AppLifecycleTests.swift` 與 `AppShellTests.swift`。
- **Suggestion（capture lease）**：design.md Decision 1 與 Contract 1、tasks.md 1.2 明寫 `handleUSBDisconnect` 先 capture generation 與 lease 再 mark。
- **Suggestion／已過濾（single-flight 機制、指派時機、迴圈等待）**：design.md Decision 3 改為以 `private(set) var userActionTask` 取代 `commandInProgress`、定義 private `runUserAction` 包裝（`Task<Result<Void, Error>, Never>` 讓 `startRoute` 的 throw 穿出）、`stopForQuit` 以 `while let` 迴圈等待；Contract 5、Risks 兩處、proposal.md、tasks.md 2.4 同步；Contract 6 與 tasks 2.2 加入「等待期間再 enqueue confirmPoint 亦被等到」案例。
- **Suggestion（replacement 起點測試）**：Contract 6 與 tasks.md 2.2 加入「舊 route 因 USB 中斷 interrupted 後 confirmPoint 的 state 歷史含 replacing → starting → reconnecting → starting → pointActive」案例。
- **Suggestion（deviceNotFound 與 setup state oracle）**：tasks.md 2.2 加入 `deviceNotFound` 映射案例與 AppShellTests 的 `DeviceSetupStore.state`／Mac 位置 request 次數不變斷言，delivery 加入 `AppShellTests.swift`；Contract 6／7 同步。disposition 校正：Reviewer A Finding 3 由 `unresolved-prior` 校正為 `new`（對應 r1 Reviewer A Finding 5 為非 blocking Suggestion）。
- **Suggestion（start current 判準）**：design.md Decision 3 第一點明寫 start 以 `state` 仍為 `reconnecting(_, sessionID)`、stop 以 `activeSessionID == sessionID` 判定；Contract 5、tasks 2.4 同步。
- **Suggestion（clear 失敗分支順序）**：design.md Decision 2 改為先同步清除 session／lease 並設 `cleanupPending`，再以 `try?` 非同步拆除 captured candidate；Contract 1、tasks.md 1.2 同步。
- **已過濾項目順帶處理**：design.md Decision 3 新增「系統睡眠與裝置中斷不造成位置跳躍」的解讀註記；Decision 6 與 tasks 2.4 明寫 reconnect 失敗來源的 `*.start_failed`／`stop_failed` 只記 case 名稱；tasks.md 2.1 success 改為「PymobiledeviceAdapterTests 以外的既有案例零失敗」。
- 修正後重新執行 `validate`：通過。修正後機械自檢：`commandInProgress` 在 design／tasks 只剩「取代」語境；Impact 的程式碼路徑集合等於 tasks delivery 路徑集合（tasks 另引用 `AppLifecycleTests.swift` 僅作 regression 目標，不屬 delivery）；七個 MODIFIED 標題逐字存在於 master。
- 修改檔案（3）：design.md、proposal.md、tasks.md。change 目錄外無修改，不呼叫 touched record。

## Decision

next_round
