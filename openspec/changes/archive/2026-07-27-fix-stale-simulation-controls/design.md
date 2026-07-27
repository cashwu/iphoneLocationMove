## Context

`AppDelegate` 在 launch 時同步建立並 publish `DeviceSetupStore`，接著以 `Task` 非同步呼叫 `DeviceSetupStore.start()`。`ContentView` 觀察 `AppDelegate`，但目前在第一次 render 時直接取值 `setupStore.simulationStore` 並傳入 `LocationMapView`。當 `connect` 完成時，`DeviceSetupStore` 先建立並 publish `SimulationStore`，再把 `state` 設為 `.ready`；只有 `DeviceSetupView` 直接觀察該 store，因此頂部狀態會更新為已就緒，而 sibling `LocationMapView` 仍持有初始的 `nil` 快照並顯示 `DisconnectedSimulationControls`。

現有 `LocationMapModel.canStartRoute` 已能正確判斷 route preview。此 bug 發生在 setup store 與 view composition 的 observation boundary，不在 MapKit、route state machine 或 device mutation 層。

## Goals / Non-Goals

Goals：

- 同一個主視窗在 `DeviceSetupStore.simulationStore` 從 `nil` 變為有效物件時立即重算定位控制內容。
- session ready 且 route preview 有效時顯示並啟用既有 `SimulationControls`，不要求關閉或重開視窗。
- 以既有 fake setup dependencies 與原生 SwiftUI hosting 建立 regression test，覆蓋 view 先建立、store 後 ready 的順序及實際 controls branch 切換。
- 保留目前 setup、地圖與 simulation feature 的責任邊界。

Non-Goals：

- 不改變 `LocationMapModel.canStartRoute`、route preview validity 或按鈕 busy gating。
- 不改變 `DeviceSetupStore.connect`、`SimulationStore` 或 device command lifecycle。
- 不導入 view inspection dependency、全域 environment object 或新的狀態管理抽象。
- 不處理 MapKit stale response、裝置切換、crash recovery 或 helper lifecycle。

## Decisions

1. 在 `ContentView.swift` 新增薄的 `DeviceSetupContentView`，以 `@ObservedObject var store: DeviceSetupStore` 直接持有 setup store。`ContentView` 仍只負責 `AppDelegate` 的 root configuration／failure 分支；一旦 `setupStore` 存在，就把整個 store 傳給新的內容 view。
2. `DeviceSetupContentView.body` 同時組合 `DeviceSetupView(store:)` 與 `LocationMapView(simulationStore: store.simulationStore)`。因 body 直接讀取 published property，`simulationStore` 建立時 SwiftUI 會重算這個共同父層，header 與定位控制使用同一份 setup snapshot。
3. 保留 `LocationMapView` 接收 optional `SimulationStore` 的小型 API，維持 disconnected preview 行為並避免 map feature 依賴整個 setup feature。
4. `DisconnectedSimulationControls` 與 `SimulationControls` 的 root container 使用穩定且互斥的 accessibility identifier，僅作為現有 UI branch 的可觀察測試 seam，不改變按鈕行為。
5. regression test 在呼叫 `DeviceSetupStore.start()` 前，以 `NSHostingView` hosting `DeviceSetupContentView` 並附加到測試用 `NSWindow`。測試先確認 disconnected identifier，完成 ready transition 並推進 main run loop 後，再於同一個 hosting view 確認 connected identifier 且 disconnected identifier 消失。此測試直接依賴 SwiftUI invalidation；若 `store` 未使用 `@ObservedObject` 或仍保存初始化 snapshot，測試 SHALL 失敗。測試不新增第三方 dependency。
6. 專案使用明確 Xcode file reference 與 Sources build phase；新增 regression test 時同步把 `ContentViewTests.swift` 登錄到 `iPhoneLocationMoveTests` target，確保 targeted 與完整 `xcodebuild test` 都會編譯及執行該測試。

## Implementation Contract

1. `iPhoneLocationMove/ContentView.swift` SHALL 定義 `DeviceSetupContentView: View`；其 `store` property SHALL 使用 `@ObservedObject`，不得保存 `store.simulationStore` 的初始化快照。
2. `ContentView.body` 在 `appDelegate.setupStore` 非 `nil` 時 SHALL render `DeviceSetupContentView(store: setupStore)`，不再於 root view 直接把 optional `simulationStore` 值傳給 `LocationMapView`。
3. `DeviceSetupContentView.body` SHALL 保留現有 vertical composition：`DeviceSetupView`、`Divider`、`LocationMapView`；後者每次 body evaluation SHALL 讀取 `store.simulationStore`。
4. `LocationMapView`、`LocationMapModel.canStartRoute`、`SimulationControls` 的 API 與 gating SHALL 保持不變。setup 尚未完成時仍 SHALL 顯示 `DisconnectedSimulationControls`；setup ready 後 SHALL 使用 `SimulationControls`。
5. `iPhoneLocationMove/Features/Map/LocationMapView.swift` SHALL 分別為 `DisconnectedSimulationControls` 與 `SimulationControls` 提供 `simulation-controls-disconnected` 與 `simulation-controls-connected` accessibility identifier；兩者 MUST NOT 同時存在於同一個 rendered controls branch。
6. `iPhoneLocationMoveTests/ContentViewTests.swift` SHALL 建立 regression test：先以 `.ready` runtime、enabled helper 與單一 supported fake device 建立 store，在 `start()` 前將 `DeviceSetupContentView` 裝入 `NSHostingView` 與測試用 `NSWindow`，驗證 disconnected identifier；呼叫 `start()` 並等待 main actor render 後，在同一 hosting view 驗證 connected identifier 且 disconnected identifier 已消失。測試 SHALL 清理測試視窗。
7. `iPhoneLocationMove.xcodeproj/project.pbxproj` SHALL 把 `iPhoneLocationMoveTests/ContentViewTests.swift` 加入 `iPhoneLocationMoveTests` group、file reference 與 test target Sources build phase；MUST NOT 只在檔案系統建立未被 target 編譯的測試檔。
8. 驗證 SHALL 至少執行 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`。

## Risks / Trade-offs

- `DeviceSetupContentView` 增加一個很薄的 composition type，但避免讓 `ContentView` 手動轉送 nested publisher 或讓 map feature 依賴 setup store。
- hosting test 依賴 macOS SwiftUI accessibility hierarchy 的 main run loop 更新，因此需要有界等待與明確 window cleanup；穩定 identifier 避免依賴本地化 label 或像素。既有 `LocationMapModelTests` 繼續驗證 route 可開始條件。
- setup store 若未來在 ready 後被替換為新的 `SimulationStore`，相同 observation boundary 也會重新 render；這符合 UI 使用 current store 的預期，但不新增任何 device switching contract。
