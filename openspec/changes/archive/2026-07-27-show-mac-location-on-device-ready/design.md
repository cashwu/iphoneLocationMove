## Context

`ContentView` 目前持續顯示 `LocationMapView`，但它只觀察 `AppDelegate`；實際觀察 `DeviceSetupStore` 的 `DeviceSetupView` 是 sibling subtree。`DeviceSetupStore.state` 與 `simulationStore` 更新時，父層不保證重算 map arguments。`LocationMapView` 以 `LocationMapModel` 保存搜尋、預覽、A／B 與路線狀態。現有 `LocationMapCanvas` 在 route 存在時每次 update 都呼叫 `setVisibleMapRect`，因此 annotation-only 更新也可能重播 route camera effect。專案尚未使用 Core Location，也沒有宣告 macOS 定位用途。

此功能需要新增一條與 iPhone DVT 完全分離的 Mac 本機定位資料流。定位回應是非同步的，可能晚於使用者搜尋、選點、拖曳地圖或裝置重新連線，因此 ownership 與 stale-result 邊界必須明確。

## Goals / Non-Goals

**Goals**

- 每個新的 ready `DeviceSessionGeneration` 在 app lifecycle 內觸發至多一次 Mac 目前位置要求，即使主視窗重建或重開。
- 使用標準 macOS Core Location `When In Use` 授權取得單次座標。
- 顯示獨立的「Mac 目前位置」標記。
- 只在使用者尚未建立地圖脈絡時自動置中一次。
- 讓授權、取消、失敗、stale response、store observation 與 camera intent 行為可用 deterministic fake 測試。

**Non-Goals**

- 不讀取 iPhone GPS，不持續追蹤 Mac，也不要求背景或 `Always` 定位。
- 不讓 Mac 座標成為預覽、A／B、路線或 iPhone 模擬位置。
- 不新增跨裝置通訊、位置持久化或 IP 位置 fallback。

## Decisions

### 1. 將 Mac 定位封裝成一次性、可注入的 client

新增 `iPhoneLocationMove/Features/Map/MacLocationClient.swift`，定義 `@MainActor protocol MacLocationProviding`、live implementation 與 app-lifetime `MacLocationCoordinator`。provider 公開 contract 只有 cancellation-aware 的 `requestCurrentLocation() async throws -> MapCoordinate`。

`LiveMacLocationClient` 每次要求建立新的 `CLLocationManager` request context，以 manager object identity 綁定 checked continuation。當 authorization 為 `.notDetermined` 時呼叫 `requestWhenInUseAuthorization()`；取得 `.authorized` 後呼叫 `requestLocation()`。`.denied`、`.restricted`、定位服務停用、delegate error、無有效座標與 task cancellation 分別映射為 typed `MacLocationClientError`。每條完成路徑都先核對 active manager identity，再恰好 resume 一次並清除 context；取消後的舊 manager callback 不得完成較新的要求。

`MacLocationCoordinator` 擁有 current ready generation、已要求 generation ledger、cached coordinate／presentation state 與 serialized transition task。generation 變成 `nil` 或換代時，transition task 先取消並等待舊 provider task 完成，再為仍屬最新的 non-nil generation 啟動要求。provider 不會同時收到兩個要求，新 generation 也不會被舊 continuation 阻塞。

provider 隱藏授權與 delegate callback；coordinator 隱藏 session ownership、window-independent deduplication 與 cancellation sequencing。刪除任一邊界都會把實質 lifecycle 行為推回 view，兩者都不是 pass-through wrapper。

### 2. 以 app-lifetime coordinator 與 store-observing shell 擁有要求

`AppDelegate` 建立並持有單一 `MacLocationCoordinator`，使 request ledger 與 cached result 不因 SwiftUI window/view lifecycle 重建而消失。`ContentView` 在取得 setup store 後建立 `LocationWorkspaceView`；該 shell 以 `@ObservedObject` 直接觀察 `DeviceSetupStore`，組合 `DeviceSetupView` 與 `LocationMapView`，並從每次 publication 衍生 optional ready generation 與最新 `simulationStore`。shell 將 generation 傳給 coordinator，再把 coordinator 的 cached coordinate／presentation 傳給 map。

舊 session、disconnect 或 replacement 的 response 由 coordinator 以 current generation 比對後丟棄，不更新 coordinate、message 或 camera。既有 `DeviceSessionGeneration` 代表裝置準備生命週期；Core Location request context 另以 manager object identity 隔離取消後的 delegate callback。

### 3. Mac marker 與一次性 camera effect 分離

`LocationMapModel` 新增獨立的 Mac 座標狀態與「使用者是否已建立地圖脈絡」旗標。搜尋開始、搜尋結果選擇、地圖選點、A／B 變更或路線要求均建立使用者脈絡。`LocationMapCanvas.Coordinator` 另回報手動平移或縮放，避免晚到的定位結果奪回 camera ownership。

成功結果一律可以更新「Mac 目前位置」marker；只有 model 與 canvas 都仍未觀察到使用者脈絡時，才發出一次 Mac initial-center intent。preview、route 與 Mac initial center 的 programmatic camera effect 都帶穩定 identity：preview 使用 coordinate identity、route 使用已接受的 `RouteRequestGeneration`、Mac initial center 使用產生 intent 的 `DeviceSessionGeneration`。`Coordinator` 分別記住最後套用的 identity，只有 identity 改變才呼叫 `setRegion` 或 `setVisibleMapRect`。因此 annotation-only／overlay redraw 不會重播既有 route fit，新的 route request 仍可合法取得 camera ownership。

### 4. 失敗為非阻塞地圖狀態

定位失敗不改變 `DeviceSetupState`、`SimulationStore` 或 map selection。UI 在地圖控制區顯示簡短訊息：權限拒絕／限制時引導使用者至系統設定；服務停用或定位失敗時說明目前無法取得 Mac 位置。失敗時不建立 marker，也不套用任何 fallback 座標，搜尋、選點與模擬控制持續可用。

### 5. 只宣告必要的隱私用途

在 `iPhoneLocationMove/Info.plist` 新增 `NSLocationUsageDescription`，文案明確說明位置只用於設定地圖初始視角。此變更不加入背景定位 capability，也不修改 iPhone 裝置權限或 privileged helper boundary。

## Implementation Contract

1. `iPhoneLocationMove/Features/Map/MacLocationClient.swift`
   - 定義 `@MainActor protocol MacLocationProviding`，唯一方法為 `requestCurrentLocation() async throws -> MapCoordinate`。
   - `LiveMacLocationClient` 每個要求擁有新的 `CLLocationManager` request context、manager identity、單一待完成 checked continuation 與 delegate callbacks。
   - 同時第二次呼叫 SHALL 以 typed error 結束，不得覆寫第一個 continuation。
   - 每次 success、denial、restriction、service-disabled、delegate-failure 或 task-cancellation completion SHALL 恰好 resume 一次並清除 in-flight ownership；舊 manager callback MUST NOT 完成新 context。
   - `MacLocationCoordinator` SHALL 由 app lifetime owner 持有，跨視窗保存已要求 generation ledger 與 cached result。
   - generation replacement SHALL 取消並等待舊要求 terminal completion，再開始最新 generation；stale completion 不得發布 state。

2. `iPhoneLocationMove/ContentView.swift`
   - `LocationWorkspaceView` SHALL 直接以 `@ObservedObject` 觀察 `DeviceSetupStore`，並同時組合 setup 與 map subtree。
   - shell 只在 `DeviceSetupState.ready` 傳遞該 session 的 `DeviceSessionGeneration`；其他狀態傳遞 `nil`。
   - 不因 Mac 定位成功而呼叫任何 `DeviceLocationClient` mutation。

3. `iPhoneLocationMove/App/iPhoneLocationMoveApp.swift`
   - `AppDelegate` SHALL 持有唯一 `MacLocationCoordinator`，並注入每個 `ContentView`；重開主視窗不得重建 request ledger。

4. `iPhoneLocationMove/Features/Map/LocationMapView.swift`
   - 觀察注入的 `MacLocationCoordinator` presentation；session transition 由 store-observing shell 傳給 coordinator。
   - stale generation 的 success 與 failure 都不得更新 marker、message 或 camera。
   - `LocationMapCanvas` 顯示 title 為「Mac 目前位置」的獨立 annotation，並將手動 camera interaction 回報給 view/model。
   - preview、route 與 Mac initial-center effect SHALL 以各自 identity 至多套用一次；annotation-only update 不得重播既有 route fit。

5. `iPhoneLocationMove/Features/Map/LocationMapModel.swift`
   - Mac marker state 不得修改 `preview`、`endpointA`、`endpointB`、`routePreview` 或 `routeStatus`。
   - 任何搜尋、選點、端點或路線互動後，晚到的 Mac 位置可以更新 marker，但不得要求 camera 置中。
   - Mac initial-center intent 每個 model lifecycle 至多產生一次；重新連線只更新 marker。
   - route camera identity SHALL 對應已接受的 `RouteRequestGeneration`，讓 canvas 可區分 redraw 與新 route。

6. `iPhoneLocationMove/Info.plist`
   - 提供非空白的 `NSLocationUsageDescription`，文案不得宣稱取得 iPhone 位置。

7. Tests
   - `iPhoneLocationMoveTests/MacLocationClientTests.swift` 以可控制的 authorization／delegate boundary 驗證 success、denial、service-disabled、delegate failure、並行要求、task cancellation、舊 manager late callback 與 continuation 單次完成。
   - `iPhoneLocationMoveTests/LocationMapModelTests.swift` 驗證初始置中資格、使用者脈絡失效、marker 與 preview／A／B／route 隔離、route identity 不因 annotation redraw 重播，以及重新連線不重置 camera intent。
   - view／shell integration test SHALL 透過同一 `DeviceSetupStore` instance 的 publication 驗證 non-ready → ready → disconnect／reconnect 會更新 map input；另驗證每代一次、pending generation replacement、stale response rejection、重開視窗不重複要求，且定位成功不產生 device mutation。

## Risks / Trade-offs

- Mac 定位可能依賴 Wi-Fi 且精度低於 iPhone GPS；UI 必須持續標示「Mac 目前位置」，不暗示是手機位置。
- 系統定位 prompt 可能在裝置就緒後才出現；這是明確授權所需的可接受中斷，拒絕後功能降級但核心模擬仍可使用。
- `CLLocationManagerDelegate` 到 async continuation 的橋接若 ownership 不完整會造成 double-resume、懸掛或舊 callback 完成新要求；以 per-request manager identity、單一 in-flight continuation、cancellation terminal path 與 boundary tests 限制風險。
- 偵測手動 MapKit camera 操作需要區分 programmatic region change；coordinator 必須在呼叫 `setRegion`／`setVisibleMapRect` 時標記 programmatic 更新，只有 user-initiated region change 才撤銷 initial-center 資格。
- app-lifetime coordinator 會保存最後 Mac 座標直到 process 結束；不寫入磁碟，且新 ready generation 成功後覆寫 cached coordinate。
