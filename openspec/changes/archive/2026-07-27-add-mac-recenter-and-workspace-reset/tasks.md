## 1. Model 層（iPhoneLocationMove/Features/Map/LocationMapModel.swift）

- [x] 1.1 新增 MacRecenterGeneration（RawRepresentable UInt64、Comparable、advanced() 溢位擲 LocationMapError.identityExhausted）、MacRecenterIntent（coordinate + generation）、LocationMapError.macLocationUnavailable（errorDescription 為「尚未取得 Mac 目前位置。」），並在 LocationMapModel 新增 macRecenterIntent、macRecenterGeneration published 屬性、canRecenterOnMac、requestMacRecenter()（無 Mac 位置擲錯；有則 recordUserMapContext() 後 advance generation 併發布新 intent）；recordUserMapContext() 擴為同時清除未消耗的 macRecenterIntent
- [x] 1.2 新增 resetWorkspace()：advance mapSearchGeneration 與 routeRequestGeneration 並清除 activeSearchRequest／activeDirectionsRequest；清空 preview、searchResults、endpointA、endpointB、routePreview、routeCameraIdentity；routeStatus 回 idle；速度回 defaultWalkingSpeed；鏡頭分支依 design Decisions 第 5 點（有 Mac 位置發布新 MacRecenterIntent，無則重設 userHasMapContext 與相關 intent）

## 2. View 層（iPhoneLocationMove/Features/Map/LocationMapView.swift）

- [x] 2.1 LocationMapCameraEffects 新增 appliedMacRecenterGeneration 與 applyMacRecenter(_:update:)（同 generation 去重、走 applyProgrammatic）；LocationMapCanvas 與 Coordinator.update 新增 macRecenterIntent 參數，於既有 route → preview → macInitialCenter 鏈之後套用新 recenter identity（同一 update 內 recenter 最後套用、勝出，依 design Decisions 第 2 點）
- [x] 2.2 controls 欄新增「到 Mac 位置」按鈕：disabled 綁 canRecenterOnMac，按下呼叫 requestMacRecenter() 並以既有 show(_:) 顯示錯誤
- [x] 2.3 將 roundTrip 與 SimulationControls 的 message @State 上移至 LocationMapView 並各以 Binding 傳入 SimulationControls（DisconnectedSimulationControls 不動）；新增純函式 ResetConfirmationContent.make(hasCleanupOwnership:) 產生兩種警語；新增「Reset」按鈕與 LocationMapView 層的獨立重置確認對話框（依 design Decisions 第 8 點）；確認後依序取消 activeSearch／activeGeocoder／activeDirections、呼叫 model.resetWorkspace()、清空 query、searchRequest、LocationMapView 自有 message 與上移後的 simulation message binding、roundTrip 關閉、執行當下有清理責任時 await simulationStore.stop() 並沿用既有 stop 失敗訊息呈現；Reset disabled 條件依 design Decisions 第 9 點

## 3. 測試

- [x] 3.1 [P] iPhoneLocationMoveTests/LocationMapModelTests.swift：requestMacRecenter 無 Mac 位置擲 macLocationUnavailable；連按兩次產生兩個遞增 identity；會清除未消耗的 macInitialCenterIntent；recordManualCameraInteraction 會清除未消耗的 macRecenterIntent
- [x] 3.2 iPhoneLocationMoveTests/LocationMapModelTests.swift：resetWorkspace 清空全部工作區狀態且速度回 4.5；重置後舊 MapSearchRequest（receiveSearchResults）、舊 MapPreviewAddressRequest（receivePreviewAddress）與舊 DirectionsRequest（receiveDirections）的回應皆判 stale 且 generation 未歸零；無 Mac 位置時重新武裝初始置中（後續 updateMacLocation 會建立 MacInitialCenterIntent）、有 Mac 位置時發布新 MacRecenterIntent
- [x] 3.3 iPhoneLocationMoveTests/LocationMapModelTests.swift：LocationMapCameraEffects.applyMacRecenter gate boundary test（與既有 CameraEffects gate 測試同置）——同一 generation 重複 update 只執行一次 camera closure、新 generation 再執行一次、redraw 不重播；ResetConfirmationContent.make(hasCleanupOwnership:) 兩分支的標題與警語內容
- [x] 3.4 [P] iPhoneLocationMoveTests/ContentViewTests.swift：沿用既有 hosting-view 測試模式驗證——reset 確認流程後 roundTrip 回關閉且搜尋框清空；模擬 busy 狀態（starting、replacing、無失敗的 stopping）時 Reset disabled；執行當下有清理責任才對 SimulationStore 發出 stop、無清理責任時不發出任何裝置命令；clear 失敗時失敗顯示與重試入口保留且工作區維持已重置
- [x] 3.5 以 xcodebuild 對 iPhoneLocationMove scheme 執行完整測試並確認全數通過
