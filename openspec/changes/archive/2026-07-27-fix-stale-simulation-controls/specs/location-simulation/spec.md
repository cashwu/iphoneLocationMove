## ADDED Requirements

### Requirement: 裝置就緒狀態與定位控制同步

系統 SHALL 讓目前主視窗的定位控制直接反映 `DeviceSetupStore` 的 current session availability。當 device session 在視窗已顯示後非同步進入 ready 並建立 `SimulationStore`，UI SHALL 在同一視窗切換為可操作的 simulation controls，MUST NOT 保留初始化時的 disconnected snapshot 或要求使用者重開視窗。

#### Scenario: 視窗顯示後裝置才完成準備

- **GIVEN** 主視窗已顯示且 device setup 尚未完成
- **AND** 定位控制目前顯示 disconnected 狀態
- **WHEN** 同一個 `DeviceSetupStore` 完成準備、建立 `SimulationStore` 並進入 ready
- **THEN** 同一個主視窗 SHALL 顯示可操作的 simulation controls
- **AND** UI MUST NOT 繼續顯示「完成裝置準備後即可使用定位控制」
- **AND** 使用者 MUST NOT 需要關閉或重開主視窗

#### Scenario: ready 後已有有效步行路線

- **GIVEN** device session ready 且目前 A/B route preview 有效
- **WHEN** `SimulationStore` availability 已發布到目前主視窗
- **THEN** 「開始步行路線」與「往返循環」SHALL 依既有 route validity 與 busy gating 啟用
- **AND** 系統 SHALL 允許使用者進入既有的開始模擬確認流程

#### Scenario: setup 尚未 ready

- **GIVEN** `DeviceSetupStore.simulationStore` 仍為 `nil`
- **WHEN** 主視窗顯示地圖與路線功能
- **THEN** 定位 mutation controls SHALL 保持停用
- **AND** 搜尋、選點與 route preview 功能 SHALL 保持可用且 MUST NOT 改變 iPhone 位置
