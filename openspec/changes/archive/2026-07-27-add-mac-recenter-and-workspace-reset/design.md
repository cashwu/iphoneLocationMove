## Context

地圖工作區狀態集中在 `LocationMapModel`（preview、searchResults、endpointA/B、routePreview、routeStatus、walkingSpeedKilometersPerHour、macLocationCoordinate、macInitialCenterIntent），以 `MapSearchGeneration` 與 `RouteRequestGeneration` 兩個單調遞增 generation 作 staleness 防護。程式化鏡頭移動由 `LocationMapCameraEffects` 去重：`applyRoute`／`applyMacCenter` 以「可消耗 identity 套用一次」模式，`applyPreview` 以座標相等去重；三者皆以 `isApplyingProgrammaticCamera` 避免把程式化移動誤判為使用者手動操作。初始置中只發生一次：`updateMacLocation(_:for:)` 在 `userHasMapContext == false` 且尚無 intent 時建立 `MacInitialCenterIntent`，之後任何使用者地圖操作都會永久關閉自動置中。

iPhone 模擬由 `SimulationStore` 擁有狀態機；停止流程已有完整契約：確認對話框（clear 語義警語）→ `stop()` → clear 失敗時停在 `stopping(_, failure)` 並保留「停止模擬」重試入口，不得假裝已恢復真實定位。`LocationMapView` 的 `SimulationControls` 以 `PendingMutation`（point／route／stop）驅動共用確認對話框；`roundTrip` 與模擬錯誤訊息 `message` 目前都是 `SimulationControls` 的 view-local `@State`。

相關 open signals：`annotation-update-camera-effect-replay`、`programmatic-camera-interaction-misclassification`、`camera-effect-gate-no-boundary-test`（camera identity 與 gate 測試）、`async-preview-stale-response`、`async-request-cancellation-generation-replacement`（generation 取代 in-flight request）、`mode-replacement-failure-state`、`mutation-terminal-state-type-split`（clear 失敗保留 cleanup ownership）、`swiftui-sibling-observation-boundary`（共同 state 由共同 shell 擁有）。

## Goals / Non-Goals

Goals：

- 使用者可隨時把地圖鏡頭帶回 Mac 目前位置，且此動作絕不改變預覽點、端點或 iPhone 定位。
- 使用者可一鍵把 Mac 端工作區重置到 App 剛啟動的狀態，並同時停止進行中的模擬；clear 失敗不被掩蓋。
- 兩顆按鈕都沿用既有機制（camera intent 去重、generation advance、`SimulationStore.stop()`），不新增狀態機。

Non-Goals：

- 不提供「把 iPhone 定位設為 Mac 位置」。
- 不改變既有「停止模擬」按鈕與其確認流程。
- 不重置裝置 session、runtime 安裝狀態或風險提醒已確認狀態。
- 不新增任何持久化。

## Decisions

1. **置中用新的可消耗 camera intent，不直接操作 MKMapView**。新增 `MacRecenterGeneration`（`UInt64` 單調遞增，`advanced()` 於溢位時擲 `LocationMapError.identityExhausted`，與既有 generation 型別同模式）與 `MacRecenterIntent`（coordinate + generation）。`LocationMapCameraEffects` 新增 `applyMacRecenter(_:update:)`，同一 generation 只套用一次，annotation redraw 不重播（對應 `annotation-update-camera-effect-replay`）；套用走 `applyProgrammatic`，不被誤判為手動操作（對應 `programmatic-camera-interaction-misclassification`）。
2. **recenter 是明確的使用者鏡頭指令，同一 update 內最後套用、勝出**。既有 route → preview → macInitialCenter 鏈維持原順序先行；`macRecenterIntent` 有新 identity 時在鏈之後套用置中，確保即使同一 `updateNSView` pass 內同時有其他新 camera identity（例如 directions 回應與按下 recenter 同一 runloop 到達），使用者剛下的明確鏡頭指令為最終結果。因為所有效果都各自去重，新 recenter identity 只套用一次，不與既有 route camera 互相重播。
3. **recenter 記錄使用者地圖脈絡，且 intent 生命週期受使用者互動約束**。`recordUserMapContext()` 擴為同時清除未消耗的 `macInitialCenterIntent` 與 `macRecenterIntent`；`requestMacRecenter()` 先呼叫 `recordUserMapContext()` 再發布新 intent，避免初始置中與 recenter 兩個 camera 指令競態，也讓任何後續使用者操作（搜尋、選點、手動平移縮放）自動清除尚未消耗的 recenter intent，界定其存活期。Mac 位置尚未取得時擲新錯誤 `LocationMapError.macLocationUnavailable`；UI 同時以 `canRecenterOnMac == false` disable 按鈕，錯誤路徑僅是防禦。
4. **reset 以 generation advance 作廢 in-flight 要求，不歸零**。`resetWorkspace()` 將 `mapSearchGeneration` 與 `routeRequestGeneration` 各 advance 一次並清除 `activeSearchRequest`／`activeDirectionsRequest` ownership；view 端同步取消 `activeSearch`／`activeGeocoder`／`activeDirections`（對應 `async-preview-stale-response`、`async-request-cancellation-generation-replacement`：舊 continuation 由 MapKit／CLGeocoder cancel 走 terminal path，stale response 由 generation guard 擋下）。
5. **reset 後的鏡頭行為分兩支**：`macLocationCoordinate` 已存在 → 直接建立新的 `MacRecenterIntent` 置中；尚未存在 → 將 `userHasMapContext` 重設為 `false` 並清空 `macInitialCenterIntent`，讓下一次 `updateMacLocation` 依既有初始置中規則重新置中，等同 App 剛啟動。既有 master spec `mac-map-initial-location` 的「初始置中不得覆寫使用者地圖脈絡」requirement 禁止 intent 套用或撤銷後重新取得 camera ownership，因此本 change 的 delta 以 MODIFIED requirement 明文授權「工作區重置」為唯一重新武裝路徑。
6. **reset 不新增模擬狀態機分支**。執行時若 `SimulationStore` 處於持有清理責任的狀態（pointActive、route、interrupted、stopping），呼叫既有 `stop()`；clear 失敗停留在 `stopping(_, failure)`，由既有 `simulationStatus` 顯示失敗與既有「停止模擬」重試入口（對應 `mode-replacement-failure-state`、`mutation-terminal-state-type-split`）。Mac 端工作區重置不等待 stop 結果，先行生效；失敗訊息照 stop 分支既有邏輯呈現。
7. **`roundTrip` 與 `SimulationControls` 的錯誤訊息 `message` 皆上移到 `LocationMapView`**，各以 `Binding` 傳入 `SimulationControls`。reset 需要清除兩者，而它們目前是 sibling 的 view-local state；由共同 shell 擁有（對應 `swiftui-sibling-observation-boundary`）。上移後 `SimulationControls` 內既有的錯誤顯示與 stop 失敗訊息寫入路徑沿用同一 binding，行為不變。`DisconnectedSimulationControls` 維持原樣。
8. **reset 確認對話框由 `LocationMapView` 持有的獨立確認 state 驅動**（不沿用 `SimulationControls` 內部 private 的 `PendingMutation` 對話框機制，避免跨元件綁定）。警語兩種：顯示對話框當下有清理責任 → 標題「確認重置並停止模擬？」、內文含既有 clear 語義句「只有手機回覆 clear 成功後，App 才會顯示已恢復真實定位。」；無清理責任（含 `simulationStore == nil` 的未連線模式）→ 標題「確認重置設定？」、內文說明會清除搜尋、A/B 端點與路線設定。警語選擇抽成純函式 `ResetConfirmationContent.make(hasCleanupOwnership:)` 以利單元測試；stop 與否仍以確認後執行當下的清理責任判定。
9. **reset 的 disabled 條件**：`simulationStore` 存在且處於 busy（starting、replacing、無失敗的 stopping）時 disabled，與既有控制項一致；未連線模式恆可用。「到 Mac 位置」按鈕在 `canRecenterOnMac == false` 時 disabled。

## Implementation Contract

- `LocationMapModel`（`iPhoneLocationMove/Features/Map/LocationMapModel.swift`）：
  - 新增 `MacRecenterGeneration`：`RawRepresentable<UInt64>`、`Comparable`、`advanced() throws`，溢位擲 `LocationMapError.identityExhausted`。
  - 新增 `MacRecenterIntent`：`coordinate: MapCoordinate` + `generation: MacRecenterGeneration`，`Equatable`、`Sendable`。
  - 新增 `@Published private(set) var macRecenterIntent: MacRecenterIntent?` 與 `@Published private(set) var macRecenterGeneration = MacRecenterGeneration(rawValue: 0)`。
  - 新增 `var canRecenterOnMac: Bool`（`macLocationCoordinate != nil`）。
  - 新增 `func requestMacRecenter() throws`：無 `macLocationCoordinate` 擲 `LocationMapError.macLocationUnavailable`；否則 `recordUserMapContext()`、advance `macRecenterGeneration`、發布新 intent。
  - 調整 `recordUserMapContext()`：除既有清除 `macInitialCenterIntent` 外，同時清除未消耗的 `macRecenterIntent`。
  - 新增 `func resetWorkspace() throws`：advance 兩個既有 generation 並清除 `activeSearchRequest`／`activeDirectionsRequest`；清空 `preview`、`searchResults`、`endpointA`、`endpointB`、`routePreview`、`routeCameraIdentity`；`routeStatus = .idle`；`walkingSpeedKilometersPerHour = Self.defaultWalkingSpeed`；鏡頭分支照 Decisions 第 5 點（有 Mac 位置 → advance `macRecenterGeneration` 併發布 intent；無 → `userHasMapContext = false` 且 `macInitialCenterIntent = nil` 且 `macRecenterIntent = nil`）。
  - `LocationMapError` 新增 case `macLocationUnavailable`，`errorDescription` 為「尚未取得 Mac 目前位置。」。
- `LocationMapView`（`iPhoneLocationMove/Features/Map/LocationMapView.swift`）：
  - controls 欄新增「到 Mac 位置」按鈕（disabled 綁 `canRecenterOnMac`）與「Reset」按鈕（disabled 條件照 Decisions 第 9 點）。
  - `roundTrip` 與 `SimulationControls` 的 `message` `@State` 皆上移至 `LocationMapView`，各以 `Binding` 傳入 `SimulationControls`。
  - reset 確認對話框由 `LocationMapView` 持有的 `@State`（例如 `isResetConfirmationPresented`）驅動；標題與內文由純函式 `ResetConfirmationContent.make(hasCleanupOwnership:)` 產生，內容照 Decisions 第 8 點。
  - 確認後執行順序：取消 `activeSearch`／`activeGeocoder`／`activeDirections` → `model.resetWorkspace()` → `query = ""`、`searchRequest = nil`、清空 `LocationMapView` 自有的 `message` 與上移後的 simulation `message` binding、`roundTrip = false` → 若執行當下 `SimulationStore` 持有清理責任則 `await simulationStore.stop()`，失敗時顯示與既有 stop 分支相同的 failure 訊息。
  - `LocationMapCanvas` 新增 `macRecenterIntent` 參數；`Coordinator.update` 先走既有 route → preview → macInitialCenter 鏈，最後以 `cameraEffects.applyMacRecenter` 處理新 recenter identity（照 Decisions 第 2 點，recenter 最後套用、勝出）。
  - `LocationMapCameraEffects` 新增 `appliedMacRecenterGeneration` 與 `applyMacRecenter(_ generation:update:)`，同 generation 去重，內部走 `applyProgrammatic`。
- 測試：
  - `iPhoneLocationMoveTests/LocationMapModelTests.swift`（與既有 `LocationMapCameraEffects` gate 測試同置）：
    - `requestMacRecenter` 無 Mac 位置擲 `macLocationUnavailable`；有 Mac 位置時 intent generation 單調遞增且連按兩次產生兩個不同 identity。
    - `requestMacRecenter` 會清除未消耗的 `macInitialCenterIntent`；`recordManualCameraInteraction` 會清除未消耗的 `macRecenterIntent`。
    - `resetWorkspace` 清空全部工作區狀態並把速度回 `4.5`。
    - `resetWorkspace` 後，舊 `MapSearchRequest` 的 `receiveSearchResults`、舊 `MapPreviewAddressRequest` 的 `receivePreviewAddress` 與舊 `DirectionsRequest` 的 `receiveDirections` 皆回 `.stale`。
    - `resetWorkspace` 在無 Mac 位置時重新武裝初始置中：後續 `updateMacLocation` 會建立 `MacInitialCenterIntent`；在有 Mac 位置時發布新的 `MacRecenterIntent`。
    - `LocationMapCameraEffects.applyMacRecenter` 的 gate boundary test：同一 generation 重複 update 只執行一次 camera closure，新 generation 再執行一次（對應 `camera-effect-gate-no-boundary-test`）。
    - `ResetConfirmationContent.make(hasCleanupOwnership:)` 兩分支的標題與警語內容。
  - `iPhoneLocationMoveTests/ContentViewTests.swift`（沿用既有 hosting-view 測試模式）：
    - reset 確認流程後 `roundTrip` toggle 回關閉、搜尋框清空。
    - 模擬 busy 狀態（starting、replacing、無失敗的 stopping）時 Reset 按鈕 disabled。
    - 執行當下有清理責任才對 `SimulationStore` 發出 stop；無清理責任時不發出任何裝置命令。
    - clear 失敗時模擬狀態區維持失敗顯示與重試入口，且工作區維持已重置。

## Risks / Trade-offs

- **reset 與 stop 併發語義**：Mac 端工作區先重置、手機端 stop 後到，期間 UI 會短暫呈現「工作區已清空但模擬狀態區仍顯示 stopping」。這是刻意行為（reset 不等待 clear），模擬狀態區是 `SimulationStore` 的唯一事實來源，不會誤報已恢復。
- **確認當下與執行當下狀態飄移**：使用者停留在對話框期間模擬狀態可能改變（例如路線自行完成）。緩解：stop 與否以執行當下的清理責任判定，警語僅為提示；最壞情況是警語比實際保守。
- **`roundTrip` 與 `message` 上移**：`SimulationControls` 介面小幅變動，屬機械性重構；`DisconnectedSimulationControls` 不動，維持行為不變。
- **`macRecenterIntent` 在 view 重建邊界的重播**：`LocationMapCanvas` 若因結構性 identity 變化重新 `makeCoordinator`，`LocationMapCameraEffects` 去重狀態歸零，殘留 intent 理論上可重播一次置中。緩解：`recordUserMapContext()` 讓任何使用者操作清除未消耗 intent，存活期與既有 `macInitialCenterIntent` 相同（該邊界為既有模式已接受的曝險）；接受殘餘風險。
- **generation 溢位**：與既有設計相同，`advanced()` 溢位擲 `identityExhausted`，reset／recenter 走各自的錯誤顯示路徑；實務上不可達。
