# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

- severity: Critical；confidence: 85；layer: design；location: design.md「Decisions 2／3」、specs/location-simulation「停止模擬時 reconnect 失敗」、tasks.md 2.2；summary: `reconnect()` 在 clear 階段失敗後 adapter 持有新 generation 的 session（`cleanupPending`）而 `SimulationStore.generation` 仍為舊值，下一次 start／stop 會收到 `staleGeneration` 而非 `usbDisconnected`，不再觸發 reconnect，且再次 reconnect 會平行建立第二個 lease；recommendation: 明定 clear 失敗時拆除 candidate tunnel／DVT、清除 session、保留 disconnected device 記錄，補 adapter 與整合測試；reviewer source: Reviewer A（Finding 1，75）與 Reviewer B（Finding 1，85）合併，layer 皆為 design
- severity: Critical；confidence: 100；layer: design；location: specs/location-simulation ADDED「未偵測 USB 中斷後的自動重新準備」 vs master「模擬模式互斥與安全取代」「單點定位模式」；summary: ADDED 行為讓第一個 mutation 失敗後最終顯示 point active／route running，與兩個未被 MODIFIED 的 master requirement（第一個 mutation 失敗 SHALL interrupted、MUST NOT 顯示 point active／route running）直接矛盾；recommendation: 以 MODIFIED 逐字承接兩個 requirement 並明文授權 `usbDisconnected` 例外；reviewer source: Reviewer A（Finding 2）

### Warning

（post-filter 無 Warning：Reviewer A Finding 3／4（75）、5／6（50）與 Reviewer B Finding 2（75）、3（65）、4（60）、5（65）confidence 落在 [50, 80) 依規則降為 Suggestion）

### Suggestion

- severity: Suggestion；confidence: 75；layer: design；location: design.md「Decisions 2」、tasks.md 2.1／2.2／2.3；summary: 測試 task 需要不存在的 seam（ResetTestSimulationDevice 無 failNextSet／reconnect 控制、RecoveryBoundary 無 exited／transportClosed 注入、FakePymobiledeviceBoundary 為 private、FakeSimulationDevice 無法觀察 state 序列）；recommendation: design 明定各 fake 的 seam；reviewer source: Reviewer A Finding 3 與 Reviewer B Finding 5、6 合併
- severity: Suggestion；confidence: 75；layer: design；location: specs/ios-device-session「沒有中斷記錄時要求重新連線」 vs tasks.md；summary: 該 scenario 沒有 task 承接；recommendation: task 1.1 增列斷言；reviewer source: Reviewer A Finding 4
- severity: Suggestion；confidence: 75；layer: design；location: specs/location-simulation Example 第三點、design.md Risks；summary: 手機未插回時 reconnect 拋 `noUSBDevice`／`deviceNotFound`，UI 會顯示「裝置尚未就緒」而非 Example 承諾的「USB 已中斷」；recommendation: 明定映射為 `usbDisconnected`；reviewer source: Reviewer B Finding 2
- severity: Suggestion；confidence: 65；layer: design；location: design.md「Decision 4」、specs/location-simulation「reconnecting 期間的控制項」；summary: `reconnecting` 持有 cleanup ownership 會顯示 enabled 的「停止模擬」按鈕，按下卻 no-op，與 `starting` 不一致；recommendation: ownership 回 false 並在 spec 明訂不顯示停止按鈕；reviewer source: Reviewer B Finding 3
- severity: Suggestion；confidence: 60；layer: design；location: design.md「Risks: generation 變為可變」、SimulationStore.stop()；summary: `stop()` 無 `commandInProgress` guard，reconnect 進行中的 stop／start／quit 可能造成第二次 reconnect、兩個 prepareSession 併發或 teardown 與 reconnect 交錯；recommendation: reconnect single-flight、quit 等待進行中動作；reviewer source: Reviewer A Finding 6 與 Reviewer B Finding 4 合併
- severity: Suggestion；confidence: 50；layer: design；location: design.md「Decisions 5」 vs master mac-map-initial-location「重新連線建立新 generation」；summary: 「只規定 MAY」敘述不準確，且 setup generation 不等於 live generation 的重新定義未出現在任何 spec delta；recommendation: 修正敘述並在 ios-device-session delta 明訂不發布新 setup ready generation；reviewer source: Reviewer A Finding 5
- severity: Suggestion；confidence: 50；layer: text；location: specs/device-tunnel-recovery「USB 已不可用」「stop cleanup recovery失敗」；summary: 未同步引用自動重備 requirement；recommendation: 補引用；reviewer source: Reviewer A Finding 7
- severity: Suggestion；confidence: 50；layer: design；location: specs/location-simulation Example、tasks.md 2.3；summary: Example 的 reconnect 成功／失敗後畫面沒有 view 測試；recommendation: 2.3 增加兩個 hosting view 案例；reviewer source: Reviewer A Finding 8
- severity: Suggestion；confidence: 50；layer: text；location: design.md「Decisions 2」、tasks.md 2.2 regression；summary: ContentViewTests 直接 conform 的 fake 只有兩個，其餘經 `DeviceSessionPreparing` 間接受影響；2.2 regression 引用的是新案例；recommendation: 列出六個具名 fake、regression 改為既有三案例；reviewer source: Reviewer A Finding 9

### 已過濾（confidence < 50，僅記錄）

- Reviewer B Finding 7（45）：exited 分支與 catch 重複記錄 `transport.recovery_failed`、metadata generation 不一致。
- Reviewer B Finding 8（40）：`teardownForQuit` 的 catch 會把 `interrupted` 覆寫為 `cleanupPending`。
- Reviewer B Finding 9（35）：`simulation.reconnect_failed` 的 `failure` 可能夾帶未 allowlist 的 message。

## Rating

- post-filter cumulative blocking set Critical count: 2
- post-filter cumulative blocking set Warning count: 0
- non-blocking triaged finding count: 9
- critical_gap: true
- round_type: full
- rationale: 首輪所有 post-filter Critical／Warning 皆為 blocking。兩個 Critical 分別證明 design 在 reconnect clear 失敗後會重回 `staleGeneration` 死局，以及 ADDED delta 與兩個既有 master requirement 直接矛盾，都必須修正後由下一輪驗證，因此本輪為 next_round。

## Fix Actions

- **Critical 1（reconnect clear 失敗死局）**：design.md Decision 2 新增 clear 失敗分支（拆除 candidate tunnel／DVT、清除 session、保留 `disconnectedDeviceID`、state `cleanupPending`、最多一個 lease），Goals 與 Risks 同步；specs/ios-device-session/spec.md requirement 正文與「重連後 clear 失敗」scenario 補三條 AND；tasks.md 1.1／1.2 加入 clear 失敗案例與實作、2.2 加入整合案例；proposal.md Proposed Solution 第 1 點同步。
- **Critical 2（ADDED 與 master 矛盾）**：specs/location-simulation/spec.md 新增 MODIFIED「模擬模式互斥與安全取代」與「單點定位模式」（標題逐字自 master 複製），在 WHEN 加入「且失敗不是可自動重備的 `usbDisconnected`，或自動重備後的重發仍失敗」並新增「已中斷的舊 session 被新模式取代」scenario；design.md Decision 3 註明此例外；proposal.md Capabilities 列出四個 MODIFIED requirement；tasks.md 2.4 標題同步。
- **Suggestion（測試 seam）**：design.md Decision 2 明列 FakeSimulationDevice、ResetTestSimulationDevice、RecoveryBoundary 的 seam；tasks.md 2.1 delivery 增加 DisconnectReconnectIntegrationTests 並列出 seam；2.2／2.3 據此改寫。
- **Suggestion（無中斷記錄的 reconnect）**：tasks.md 1.1 增列斷言；design Implementation Contract 2 同步。
- **Suggestion（noUSBDevice 呈現）**：design.md Decision 3 新增 reconnect 失敗分類；specs/location-simulation requirement 正文、「reconnect 失敗」scenario 與 Example 同步；tasks.md 2.2 加入 `noUSBDevice`／`deviceLocked` 案例；proposal.md 同步。
- **Suggestion（reconnecting 的 cleanup ownership）**：design.md Decision 4 改為 ownership false；specs/location-simulation requirement 正文與「reconnecting 期間的控制項」scenario 改為不顯示停止按鈕；tasks.md 2.3／2.4 同步。
- **Suggestion（single-flight／quit）**：design.md Decision 3 新增 `stop()` 的 `commandInProgress` guard、`userActionTask`、`stopForQuit` 等待、`hasActiveSimulation` 擴充、回寫前 sessionID 驗證；specs/location-simulation requirement 正文與新增「reconnect 進行中的其他要求與退出」scenario；tasks.md 2.2／2.4 同步；Implementation Contract 9 註明 AppLifecycleCoordinator 不變。
- **Suggestion（mac-map 敘述）**：design.md Decision 5 改寫；specs/ios-device-session requirement 正文與「上層經由 client seam 觸發重新連線」scenario 加入不發布 setup ready generation、不觸發 Mac 位置要求。
- **Suggestion（device-tunnel-recovery 引用）**：specs/device-tunnel-recovery「USB 已不可用」「stop cleanup recovery失敗」各補一條 AND 引用自動重備 requirement。
- **Suggestion（Example 的 view 測試）**：tasks.md 2.3 增加 resume 後無錯誤區、失敗後「模擬已中斷／USB 已中斷」兩案例；specs/location-simulation 新增「reconnect 結束後的側欄」scenario；design Decision 4 同步。
- **Suggestion（fake 數量與 regression）**：design.md Decision 2 列出六個具名 fake 並註明 `DeviceSessionPreparing` refine；tasks.md 2.2 regression 改為既有三案例。
- **已過濾項目順帶處理**：design.md Decision 1／6 明定 `transport.recovery_failed` 只由 catch 記錄一次、`recoveryMetadata` 用 captured generation、`simulation.reconnect_failed` 只記 case 名稱；tasks.md 1.1／2.2 加入對應斷言；`teardownForQuit` 覆寫行為記入 Risks 為既有行為不處理。
- 修正後重新執行 `validate`：通過。修正後機械自檢：註解配對 0／0、六個 MODIFIED 標題逐字存在於 master、所有新識別字在 design 與 tasks 一致、Impact 與 tasks 路徑集合相同。
- 修改檔案（6）：proposal.md、design.md、specs/device-tunnel-recovery/spec.md、specs/ios-device-session/spec.md、specs/location-simulation/spec.md、tasks.md。change 目錄外無修改，不呼叫 touched record。

## Decision

next_round
