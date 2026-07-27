# device-tunnel-recovery Specification

## Purpose

device-tunnel-recovery capability.

## Requirements

### Requirement: 結構化辨識 transport 中斷

系統 SHALL 將 DVT backend 的 transport closure 與其他 backend failure 分開回報，MUST NOT只以localized UI message substring決定是否自動恢復。helper response MAY包含bounded exception detail；persistent diagnostic SHALL只記錄allowlisted failure code、exception type、errno、目前tunnel lease state、可用的process termination status與stderr byte count，MUST NOT記錄raw exception message、stderr tail、座標或RSD endpoint。

#### Scenario: RSD route 在定位更新期間消失

- **GIVEN** 同一台 USB iPhone 的 route mutation 正在使用 current tunnel／DVT transport
- **WHEN** DTX reader 回報 `No route to host`，且 request 以 `ConnectionTerminatedError: Connection closed` 結束
- **THEN** helper SHALL 回傳 structured `transport-closed` failure
- **AND** adapter SHALL probe current tunnel lease status
- **AND** diagnostic log SHALL 記錄transport classification、lease state與allowlisted process fields
- **AND** diagnostic log MUST NOT包含raw backend detail、stderr tail、座標或RSD endpoint

#### Scenario: 非 transport backend failure

- **WHEN** DVT backend 回傳不屬於已定義 socket／route closure 類型的 exception
- **THEN** helper SHALL 回傳 `backend-failure`
- **AND** 系統 MUST NOT 對該 failure 自動重建 tunnel

#### Scenario: tunnel process 已退出

- **GIVEN** caller 擁有 current tunnel lease
- **WHEN** status probe 發現 tunnel process 已退出
- **THEN** privileged helper SHALL 回傳 `exited` snapshot及 termination status與最多 4 KiB stderr tail
- **AND** privileged helper SHALL 移除該失效 lease ownership

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

### Requirement: 每筆 mutation 最多執行一次 transport recovery

系統 SHALL對符合資格的`set`或`clear` structured `transport-closed` failure執行最多一次序列化recovery。recovery SHALL回收舊DVT／tunnel transport、建立新的transport identity，並只重播原本的絕對mutation一次；系統 MUST NOT對local helper exit、tunnel status `exited`或非transport backend failure執行recovery，也 MUST NOT遞迴recovery或形成無限retry。

#### Scenario: set 在新 transport replay 成功

- **GIVEN** current route mutation因 structured `transport-closed` 失敗
- **AND** 同一台 USB iPhone仍可建立 tunnel與DVT session
- **WHEN** adapter完成 recovery並在新 transport重播同一 logical `set`
- **THEN** logical mutation SHALL 回報 success
- **AND** 同一 `SimulationSessionID` SHALL 繼續執行既有 route
- **AND** confirmed route progress SHALL 只提交一次

#### Scenario: clear 在新 transport replay 成功

- **GIVEN** 使用者停止模擬時 current transport已中斷
- **WHEN** adapter重建 transport並重播同一 logical `clear`
- **THEN** 系統 SHALL 只在 clear success後釋放 simulation ownership
- **AND** UI SHALL 顯示已恢復真實定位

#### Scenario: recovery replay 再次失敗

- **GIVEN** 一筆 logical mutation已執行一次 transport recovery
- **WHEN** 新 transport上的 replay仍失敗
- **THEN** 系統 MUST NOT 再次 recovery
- **AND** 該 logical mutation最多 SHALL 有兩次 device delivery attempt
- **AND** 系統 SHALL 回報 typed terminal failure

#### Scenario: 舊 tunnel 無法安全停止

- **GIVEN** status顯示舊 tunnel process仍在執行
- **WHEN** `stopTunnel` 失敗
- **THEN** 系統 SHALL 中止 recovery
- **AND** 系統 MUST NOT 平行建立第二個 tunnel lease

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

### Requirement: transport replacement 隔離 stale completion

系統 SHALL以獨立於logical`DeviceSessionGeneration`的transport identity隔離每個tunnel／DVT pair，並 SHALL使用另一個獨立recovery ownership epoch取消跨`await`的recovery transaction。取消recovery ownership MUST NOT使仍須執行old-device clear的current transport identity失效。每個recovery external side effect前後 SHALL重新驗證captured recovery epoch、device identity、logical generation、old transport generation與lease ownership。系統 SHALL在candidate tunnel啟動後先保存candidate generation與lease ID，並僅在candidate DVT helper啟動且取得handle後組成完整transaction-scoped candidate identity；完整identity建立前失敗時仍 SHALL清理已取得的candidate資源。candidate replay reply SHALL以完整candidate identity驗證並只保存為local result，MUST NOT因candidate尚未current而判為stale，也 MUST NOT在candidate atomically commit前發布logical mutation success。transport replacement MUST NOT建立新的logical ready session；來自舊transport的reply、stderr callback或shutdown completion MUST NOT改寫新transport ownership或route state。

#### Scenario: recovery 不替換 logical ready session

- **GIVEN** current device session generation為 G，route session為 S
- **WHEN** adapter成功重建 tunnel／DVT transport
- **THEN** logical device session generation SHALL 維持 G
- **AND** route session SHALL 維持 S
- **AND** 系統 MUST NOT 因這次 transport replacement重新要求 Mac目前位置

#### Scenario: 舊 transport completion 晚到

- **GIVEN** transport T1 已被 T2 取代
- **WHEN** T1 的 reply或callback在 T2 ready後到達
- **THEN** 系統 SHALL 依 transport identity忽略 T1 completion
- **AND** T1 completion MUST NOT 清除或覆寫 T2 lease／DVT ownership

#### Scenario: candidate replay 在 commit 前成功

- **GIVEN** recovery已建立尚未成為current的candidate transport T2
- **WHEN** T2 replay回傳success
- **THEN** 系統 SHALL以candidate identity接受transaction-local result
- **AND** 系統 MUST NOT套用一般current-transport gate把T2 reply判為stale
- **AND** 系統 MUST NOT在recovery ownership再次驗證且T2 atomically commit前發布logical mutationsuccess

#### Scenario: recovery 期間 scheduler 繼續 tick

- **GIVEN** 一筆 route mutation正在執行 transport recovery
- **WHEN** scheduler產生更多 tick
- **THEN** 系統 SHALL 維持最多一筆 in-flight device mutation
- **AND** 系統 MUST NOT 在 recovery transaction之前派送另一筆座標

#### Scenario: disconnect 在 recovery await 期間插入

- **GIVEN** recovery正等待status、candidate tunnel、DVT start或replay完成
- **WHEN** USB disconnect、reconnect、device switch或quit teardown使captured ownership失效
- **THEN** recovery SHALL在下一個external side effect前停止
- **AND** recovery MUST NOT重播stale座標
- **AND** recovery SHALL清理本transaction已建立的candidate資源
- **AND** recovery MUST NOT清除或覆寫較新的current session資源
- **AND** switch或quit cleanup SHALL仍可對正確old device執行序列化clear

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

### Requirement: recovery terminal state 依 mutation 類型分流

active `set`的recovery、new tunnel／DVT start或mutation replay無法完成時，系統 SHALL停止route producer，並將active simulation標示為`interrupted(positionUnknown)`；系統 MUST NOT宣稱最後target已套用，也 MUST NOT自動從不確定位置繼續移動。`clear`的相同failure則 SHALL保留stopping／cleanup ownership與retry clear，MUST NOT回到idle或宣稱已恢復真實定位。

#### Scenario: USB 已不可用

- **GIVEN** transport failure後同一台 iPhone已不再可透過USB建立 tunnel
- **WHEN** recovery start失敗
- **THEN** route SHALL 進入 `interrupted(positionUnknown)`
- **AND** UI SHALL 提供 typed reconnect／重新準備動作

#### Scenario: recovery 成功

- **WHEN** recovery與原 mutation replay皆成功
- **THEN** route SHALL 保持 running並從已確認進度繼續
- **AND** UI MUST NOT 顯示 terminal interruption

#### Scenario: stop cleanup recovery失敗

- **GIVEN** active simulation仍擁有可能殘留的裝置位置
- **WHEN** clear recovery失敗
- **THEN** 系統 SHALL 保留 cleanup ownership與 retry clear動作
- **AND** UI MUST NOT 宣稱已恢復真實定位

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
