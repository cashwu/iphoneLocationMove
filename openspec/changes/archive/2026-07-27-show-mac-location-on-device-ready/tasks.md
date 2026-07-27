## 1. TDD：建立失敗測試

- [x] [P] 1.1 在 `iPhoneLocationMoveTests/MacLocationClientTests.swift` 建立可控制 Core Location boundary，先寫 success、`notDetermined` 授權後成功、`denied`、`restricted`、service-disabled、delegate failure、無效座標、並行要求、task cancellation、舊 manager late callback 與 continuation 只完成一次的失敗測試。
- [x] [P] 1.2 在 `iPhoneLocationMoveTests/LocationMapModelTests.swift` 先寫 Mac marker 獨立性、首次置中資格、搜尋／選點／端點／路線使置中失效、手動 camera interaction、重新連線只更新 marker，以及 annotation redraw 不重播既有 route camera identity 的失敗測試。
- [x] [P] 1.3 在 `iPhoneLocationMoveTests/AppShellTests.swift` 先寫同一 `DeviceSetupStore` instance 發布 non-ready → ready → disconnect／reconnect、每個 ready `DeviceSessionGeneration` 只要求一次、pending A 被 B 取代、舊 generation 結果不更新 UI、重開視窗不重複要求，以及成功結果不產生 `DeviceLocationClient.setLocation` 的 integration contract 測試。

## 2. 實作 Mac 一次性定位 client

- [x] 2.1 在 `iPhoneLocationMove/Features/Map/MacLocationClient.swift` 定義 `MacLocationProviding`、`MacLocationClientError`、per-request manager context、`LiveMacLocationClient` 與 app-lifetime `MacLocationCoordinator`；以 cancellation-aware checked continuation 實作 `When In Use` 授權、一次性 `requestLocation()`、manager identity 隔離、serialized generation replacement、跨視窗 request ledger、typed terminal errors、並行要求拒絕及恰好一次完成。
- [x] 2.2 在 `iPhoneLocationMove/Info.plist` 新增非空白 `NSLocationUsageDescription`，明確說明只用於地圖初始視角且不宣稱取得 iPhone 位置。
- [x] 2.3 執行 `xcodegen generate --spec iPhoneLocationMove/project.yml --project . --project-root .`，將新 production／test source 同步至 `iPhoneLocationMove.xcodeproj/project.pbxproj`，並確認未引入無關 project 設定變更。

## 3. 實作地圖 ownership 與 UI 整合

- [x] 3.1 在 `iPhoneLocationMove/Features/Map/LocationMapModel.swift` 實作獨立 Mac marker state、一次性 initial-center intent、使用者地圖脈絡失效規則與可消耗的 route camera identity，使 1.2 測試通過。
- [x] 3.2 在 `iPhoneLocationMove/ContentView.swift` 新增直接以 `@ObservedObject` 觀察 `DeviceSetupStore` 的 `LocationWorkspaceView`，由它組合 setup／map subtree、傳遞 `.ready` generation 與最新 `simulationStore`，且不把 Mac 定位接到任何 device mutation path。
- [x] 3.3 在 `iPhoneLocationMove/App/iPhoneLocationMoveApp.swift` 讓 `AppDelegate` 建立並持有唯一 `MacLocationCoordinator`，再注入每個 `ContentView`，使同一 ready generation 不因主視窗重建而重複要求。
- [x] 3.4 在 `iPhoneLocationMove/Features/Map/LocationMapView.swift` 觀察注入的 `MacLocationCoordinator`、顯示非阻塞失敗訊息，並擴充 `LocationMapCanvas` 顯示唯一「Mac 目前位置」marker、依 preview／route／Mac intent identity 至多套用一次 camera effect，以及回報 user-initiated pan／zoom；programmatic region change 與 annotation-only redraw 不得誤判或重播 camera effect。
- [x] 3.5 讓 `iPhoneLocationMoveTests/MacLocationClientTests.swift`、`iPhoneLocationMoveTests/LocationMapModelTests.swift` 與 `iPhoneLocationMoveTests/AppShellTests.swift` 全部通過，並確認 async stale-response case 使用可控制 fake 而非 wall-clock delay。

## 4. 驗證與 acceptance

- [x] 4.1 執行 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`，修正所有失敗。
- [x] 4.2 在可授權定位的 Mac 上執行 acceptance：首次 ready 顯示系統授權 prompt；允許後顯示「Mac 目前位置」並只置中一次；先搜尋、選點、平移或縮放時，晚到結果只更新 marker；route fit 後手動移動 camera 再更新 marker 時不重播 route fit；拒絕或停用定位時仍可搜尋及控制模擬。
- [x] 4.3 以 spy `DeviceLocationClient` 驗證整個 acceptance 流程沒有因 Mac 定位 success 或 failure 產生 `setLocation`，並檢查 marker 文案始終稱為「Mac 目前位置」。
