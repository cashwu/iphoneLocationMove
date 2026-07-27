# location-simulation Specification

## Purpose

location-simulation capability.

## Requirements

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

<!-- @trace
source: fix-stale-simulation-controls
updated: 2026-07-27
code:
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/ContentView.swift
  - iPhoneLocationMove/Features/Map/LocationMapView.swift
  - iPhoneLocationMoveTests/ContentViewTests.swift
tests:
-->

### Requirement: 可恢復 transport closure 的中斷判定

系統 SHALL將structured `transport-closed`與terminal helper／tunnel failure分開處理。對符合`device-tunnel-recovery` contract的single-in-flight mutation，系統 SHALL在one-shot recovery terminal前將completion視為recoverable pending，MUST NOT提前發布running success或`interrupted`。active `set` recovery success後 SHALL沿用既有active session，recovery failure後 SHALL依既有裝置中斷contract進入`interrupted(positionUnknown)`；`clear` recovery failure則 SHALL保留stopping／cleanup ownership與retry clear，MUST NOT回到idle。`set` timeout、local DVT helper exit、tunnel status `exited`、non-transport backend failure及無法驗證ownership的completion MUST NOT套用此例外。

#### Scenario: structured transport closure recovery成功

- **GIVEN** active route或point session有一筆single-in-flight absolute mutation
- **WHEN** 該mutation回傳structured `transport-closed`，且one-shot recovery與同一mutation replay成功
- **THEN** 系統 SHALL保持原本的`SimulationSessionID`
- **AND** route或point session SHALL維持active
- **AND** confirmed mutation result SHALL只提交一次

#### Scenario: structured transport closure recovery失敗

- **GIVEN** active route或point session正在處理structured `transport-closed`
- **WHEN** ownership gate、transport rebuild或mutation replay失敗
- **THEN** 系統 SHALL立即停止producer並進入`interrupted(positionUnknown)`
- **AND** UI MUST NOT繼續顯示running或active
- **AND** 系統 SHALL提供對current device ownership的reconnect／clear或retry路徑

#### Scenario: clear recovery失敗

- **GIVEN** simulation正在執行clear且仍擁有可能殘留的裝置位置
- **WHEN** ownership gate、transport rebuild或clear replay失敗
- **THEN** 系統 SHALL保持stopping／cleanup ownership與retry clear
- **AND** UI MUST NOT顯示running、idle或已恢復真實定位

#### Scenario: terminal helper或tunnel failure

- **WHEN** active route或point session遇到`set` timeout、local DVT helper exit、tunnel status `exited`、non-transport backend failure或無法驗證ownership的completion
- **THEN** 系統 SHALL立即停止producer並進入`interrupted(positionUnknown)`
- **AND** 系統 MUST NOT自動建立replacement tunnel

<!-- @trace
source: recover-dropped-device-tunnel
updated: 2026-07-27
code:
  - iPhoneLocationMove/Device/DeviceLocationClient.swift
  - iPhoneLocationMove/Device/PymobiledeviceAdapter.swift
  - iPhoneLocationMove/Device/TunnelHelperXPCProtocol.h
  - iPhoneLocationMove/Features/Simulation/SimulationStore.swift
  - iPhoneLocationMoveHelper/PROTOCOL.md
  - iPhoneLocationMoveHelper/helper.py
  - iPhoneLocationMoveHelper/tests/test_protocol.py
  - iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift
  - iPhoneLocationMoveTests/SimulationStoreTests.swift
  - iPhoneLocationMoveTests/TunnelHelperContractTests.swift
  - iPhoneLocationMoveTunnelHelper/main.swift
tests:
-->
