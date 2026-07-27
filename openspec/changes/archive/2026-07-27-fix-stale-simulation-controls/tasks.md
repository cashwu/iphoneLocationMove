## 1. Regression coverage

- [x] 1.1 依 `.cash.yaml` 的 TDD workflow，在新的 `iPhoneLocationMoveTests/ContentViewTests.swift` 建立 regression test，並修改 `iPhoneLocationMove.xcodeproj/project.pbxproj`，把該檔案加入 `iPhoneLocationMoveTests` group、file reference 與 test target Sources build phase。測試於 `DeviceSetupStore.start()` 前把 `DeviceSetupContentView` 裝入 `NSHostingView` 與測試用 `NSWindow`，先驗證 `simulation-controls-disconnected`，再讓 fake runtime／helper／單一 supported device 完成 ready transition、推進 main run loop，並在同一 hosting view 驗證 `simulation-controls-connected` 出現且 disconnected identifier 消失；測試須有界等待並清理 window。先執行該 test，確認 test target 確實編譯執行它，且 snapshot-based composition 無法完成 controls branch 切換。

## 2. UI observation fix

- [x] 2.1 在 `iPhoneLocationMove/ContentView.swift` 新增以 `@ObservedObject` 持有 `DeviceSetupStore` 的 `DeviceSetupContentView`，由它共同組合 `DeviceSetupView` 與 `LocationMapView(simulationStore: store.simulationStore)`；調整 `ContentView` 傳遞整個 setup store，且不修改 route validity 或 simulation mutation API。
- [x] 2.2 在 `iPhoneLocationMove/Features/Map/LocationMapView.swift` 為 disconnected／connected controls root container 分別加入 `simulation-controls-disconnected`／`simulation-controls-connected` accessibility identifier，不改變 controls 的按鈕、gating 或 mutation 行為。
- [x] 2.3 重新執行 1.1 的 targeted test，確認同一 hosting view 在 setup ready 後切換 accessibility branch，並確認既有 `DeviceSetupStoreTests` 與 `LocationMapModelTests` 通過。

## 3. Verification

- [x] 3.1 執行 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`，確認完整 macOS test suite 通過。
- [x] 3.2 檢查 `ContentView` composition：setup 尚未 ready 時仍傳入 `nil` 並顯示 disconnected controls；ready 後 body 直接讀取 current `store.simulationStore` 並顯示 `SimulationControls`，且既有 route preview、risk confirmation 與 busy gating 未變更。
