## Summary

修正 macOS App 在同一視窗內完成非同步裝置準備後，定位控制仍停留在 disconnected／disabled 狀態的問題。讓地圖與定位控制直接觀察 `DeviceSetupStore`，並在 `simulationStore` 建立時立即切換為可操作控制。

## Motivation

這是 Bug Fix。App 啟動時 `ContentView` 先取得尚未準備完成的 `setupStore.simulationStore`（值為 `nil`），並把該快照傳給 `LocationMapView`。之後 `DeviceSetupStore` 已顯示 device session ready 並建立 `SimulationStore`，但擁有地圖控制的 view hierarchy 沒有觀察這個 nested observable object，因此畫面仍顯示「完成裝置準備後即可使用定位控制」，「設定位置」、「往返循環」與「開始步行路線」持續停用。使用者只能關閉並重開視窗才能取得最新狀態，違反 ready 後應可立即開始模擬的既有行為。

## Proposed Solution

在 setup store 已建立後，使用一個直接以 `@ObservedObject` 持有 `DeviceSetupStore` 的內容 view，同時組合 `DeviceSetupView` 與 `LocationMapView`。當 `simulationStore` 從 `nil` 變為有效物件時，該內容 view 重新計算 body，讓 `LocationMapView` 收到目前的 store 並顯示 `SimulationControls`。

保留既有 `LocationMapModel.canStartRoute`、裝置 mutation、風險確認與 route session 邏輯；只修正 setup/session 狀態到 UI 的 observation boundary。為 connected／disconnected controls 加入穩定 accessibility identifier，並以原生 `NSHostingView` regression test 驗證同一個 hosting hierarchy 在 `DeviceSetupStore` 轉為 ready 後切換 controls，不需重建主視窗。

## Non-Goals

- 不改變 MapKit 搜尋、A/B 選點、directions generation 或 route preview 規則。
- 不改變 `SimulationStore`、`RouteSession` 或 device adapter 的 mutation 行為。
- 不新增第三方 view inspection dependency 或 UI 架構層。
- 不處理 App crash／relaunch、裝置切換或 privileged helper lifecycle。

## Alternatives Considered

- 在 `ContentView` 對 `simulationStore` 狀態加 `.id(...)`：父 view 本身未觀察 `DeviceSetupStore`，無法可靠收到 nested property 更新，因此不能解決根因。
- 讓 `LocationMapView` 直接持有整個 `DeviceSetupStore`：可行但把 setup concern 擴散到 map feature；由一個薄的內容組合 view 負責 observation，邊界更小且更清楚。
- 加入第三方 SwiftUI inspection library：此修正不需要額外 dependency；可透過原生 `NSHostingView`、穩定 accessibility identifier 與既有 store fake 驗證。

## Capabilities

### New Capabilities

- (none)

### Modified Capabilities

- `location-simulation`：補充 device session 在既有視窗內非同步進入 ready 後，定位控制必須立即使用新建立的 `SimulationStore`，不得維持 disconnected／disabled UI。

## Impact

- Affected specs:
  - `location-simulation`
- Affected code:
  - New:
    - `iPhoneLocationMoveTests/ContentViewTests.swift`
  - Modified:
    - `iPhoneLocationMove.xcodeproj/project.pbxproj`
    - `iPhoneLocationMove/ContentView.swift`
    - `iPhoneLocationMove/Features/Map/LocationMapView.swift`
  - Removed:
    - (none)
