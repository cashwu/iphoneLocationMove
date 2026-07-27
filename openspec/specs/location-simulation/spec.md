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

### Requirement: 地圖搜尋、選點與明確確認

系統 SHALL 使用 MapKit 顯示地圖，支援地名／地址搜尋與直接點擊選點。搜尋或點擊只 SHALL 更新 preview marker、地址與座標，MUST NOT 立即改變 iPhone 位置。

#### Scenario: 搜尋並預覽地點

- **WHEN** 使用者搜尋地名或地址並選擇結果
- **THEN** 系統 SHALL 將地圖移至結果並顯示 preview marker、地址與座標
- **AND** iPhone 定位 MUST 保持不變

#### Scenario: 舊搜尋結果晚到

- **GIVEN** 使用者已送出較新的搜尋 query
- **WHEN** 較舊 query 的 MapKit response 較晚到達
- **THEN** 系統 SHALL 以 `MapSearchGeneration` 忽略舊 response
- **AND** current preview MUST 保持對應最新 query

#### Scenario: 直接點擊地圖

- **WHEN** 使用者點擊有效地圖座標
- **THEN** 系統 SHALL 遞增 `MapSearchGeneration`、取消可取消的 in-flight search，並更新 preview marker 與座標
- **AND** 系統 SHALL 等待使用者明確選擇「設定位置」或將點指定為 A／B

#### Scenario: 點擊地圖後舊搜尋結果晚到

- **GIVEN** search request 尚未完成
- **WHEN** 使用者直接點擊地圖取代 preview，之後舊 search response 到達
- **THEN** 系統 SHALL 忽略舊 response
- **AND** current preview SHALL 保持為使用者點擊的座標

<!-- @trace
source: add-macos-location-simulator
updated: 2026-07-27
code:
tests:
-->

### Requirement: 單點定位模式

系統 SHALL 提供獨立的單點定位模式。只有在 device session ready 且使用者確認 preview coordinate 後，系統才 SHALL 設定 iPhone 位置，並持有該位置直到使用者停止模擬、切換至另一個已確認模式或退出 App。

#### Scenario: 確認單點定位

- **GIVEN** device session ready 且已有有效 preview coordinate
- **WHEN** 使用者按下「設定位置」
- **THEN** 系統 SHALL 建立新的 `SimulationSessionID` 並設定該座標
- **AND** UI SHALL 在收到 device success 後顯示 point active

#### Scenario: 設定單點失敗

- **WHEN** device adapter 無法確認座標設定成功
- **THEN** 系統 SHALL 顯示 typed error 與重試動作
- **AND** 系統 MUST NOT 顯示 point active

#### Scenario: 單點維持到明確停止

- **GIVEN** point simulation active
- **WHEN** 使用者未按「停止模擬」且 App 未真正退出
- **THEN** 系統 SHALL 維持目前模擬位置

<!-- @trace
source: add-macos-location-simulator
updated: 2026-07-27
code:
tests:
-->

### Requirement: A/B 步行路線預覽

系統 SHALL 讓使用者分別選擇 A 與 B，使用 MapKit pedestrian directions 產生 immutable route preview，並在開始前顯示 polyline、距離、目前速度下的 ETA 與 `往返循環` 選項。

#### Scenario: 成功產生步行路線

- **WHEN** 使用者已指定不同的 A、B 且 MapKit 回傳 pedestrian route
- **THEN** 系統 SHALL 顯示該路線的 polyline、總距離與 ETA
- **AND** 系統 SHALL 允許使用者確認開始

#### Scenario: 沒有步行路線

- **WHEN** MapKit 無法為 A、B 產生 pedestrian route
- **THEN** 系統 SHALL 顯示無可用步行路線
- **AND** 系統 SHALL 保留 A、B 供使用者修改
- **AND** 開始控制 MUST 保持停用

#### Scenario: directions 暫時失敗

- **WHEN** MapKit directions 因離線或暫時服務錯誤失敗
- **THEN** 系統 SHALL 保留 A、B 並顯示可重試錯誤
- **AND** 系統 MUST NOT 把 transient failure 描述為確定沒有步行路線

#### Scenario: A 或 B 在 directions 執行中改變

- **GIVEN** 舊 A／B snapshot 的 directions request 尚未完成
- **WHEN** 使用者改變 A 或 B
- **THEN** 系統 SHALL 取消可取消的舊 request，否則以 `RouteRequestGeneration` 忽略舊 response
- **AND** 使用者開始前系統 SHALL 再次驗證 route preview 對應目前 A、B

#### Scenario: 路線預覽後 MapKit 資料改變

- **GIVEN** 使用者已確認並開始 route session
- **WHEN** 外部 directions 資料之後改變
- **THEN** active session SHALL 繼續使用開始時確認的 immutable polyline
- **AND** 系統 MUST NOT 在途中靜默換線

<!-- @trace
source: add-macos-location-simulator
updated: 2026-07-27
code:
tests:
-->

### Requirement: 步行速度與距離進度

route session SHALL 以 monotonic elapsed time、速度與 pedestrian polyline cumulative distance 計算位置。預設速度 SHALL 為 `4.5 km/h`，可選範圍 SHALL 為 `1–7 km/h`，位置更新目標頻率 SHALL 約為每秒一次。

#### Scenario: 以預設速度開始

- **GIVEN** 使用者未改變預設速度
- **WHEN** 使用者確認開始 route session
- **THEN** 系統 SHALL 先把 iPhone 設定到 A
- **AND** 系統 SHALL 以 `4.5 km/h` 沿已確認 polyline 朝 B 前進

#### Scenario: timer 延遲

- **WHEN** 某次 tick 晚於目標時間執行
- **THEN** 系統 SHALL 依實際 monotonic elapsed time 計算當前距離
- **AND** 系統 MUST NOT 只累加固定的每 tick 距離

##### Example: 900 公尺單程

對一條總長 `900 m` 的 route，速度 `4.5 km/h` 等於 `1.25 m/s`，未暫停時抵達 B 的預估時間為 `720 seconds`，即 `12 minutes`。

<!-- @trace
source: add-macos-location-simulator
updated: 2026-07-27
code:
tests:
-->

### Requirement: 暫停、繼續與即時調速

系統 SHALL 允許 active route 暫停及繼續。暫停時 SHALL 維持當前模擬位置且停止 route tick；改變速度時 SHALL 先建立 command barrier，並以 barrier 完成時的 latest confirmed distance 作為當前距離 rebase。新速度 SHALL 影響後續進度，且 committed progress 與裝置座標 MUST NOT 因調速而倒退或跳躍。

#### Scenario: 暫停路線

- **WHEN** 使用者暫停 running route
- **THEN** 系統 SHALL snapshot last confirmed coordinate／distance 並停止新的位置更新
- **AND** iPhone SHALL 維持暫停座標

#### Scenario: 繼續路線

- **GIVEN** route session paused
- **WHEN** 使用者選擇繼續
- **THEN** 系統 SHALL 從 paused distance 與新的 monotonic baseline 繼續
- **AND** 暫停經過的時間 MUST NOT 計入移動距離

#### Scenario: 執行中調整速度

- **GIVEN** route session running 或 paused
- **WHEN** 使用者將速度調整到合法範圍內的新值
- **THEN** 系統 SHALL 使舊 `RouteUpdateEpoch` 失效、清除 pending coordinate 並等待 current in-flight mutation
- **AND** mutation success 後系統 SHALL 保留 latest confirmed distance，以新的 monotonic baseline 與速度計算後續 ETA 與進度
- **AND** 未確認的 tick target MUST NOT 被發布為 committed progress
- **AND** 若 mutation 結果不確定，系統 SHALL 進入 `interrupted(positionUnknown)`

<!-- @trace
source: add-macos-location-simulator
updated: 2026-07-27
code:
tests:
-->

### Requirement: 路線更新背壓與操作屏障

系統 SHALL 讓 route update 同時最多一個 device `set` request in flight。tick 累積時 SHALL 只保留 current `RouteUpdateEpoch` 的最新 pending coordinate；pause、sleep pause、speed rebase、mode replacement、stop 與 clear SHALL 先使舊 epoch 失效並建立 command barrier。pause 只有在 last confirmed coordinate 等於 pause snapshot 後才 SHALL 完成；若 snapshot 已是 last confirmed coordinate 且沒有 in-flight mutation，MUST NOT 為了 pause 額外送出 device mutation。

#### Scenario: DVT update 慢於 tick

- **GIVEN** current route `set` request 尚未完成
- **WHEN** 一個或多個新 tick 產生
- **THEN** 系統 SHALL 只保留最新 pending coordinate
- **AND** 系統 MUST NOT 排隊重播所有中間座標

#### Scenario: request in flight 時暫停

- **GIVEN** route update request in flight
- **WHEN** 使用者暫停或 macOS 即將 sleep
- **THEN** 系統 SHALL 進入 `pausing`，snapshot 當前 confirmed coordinate／distance，使舊 `RouteUpdateEpoch` 失效並清除 pending coordinate
- **AND** 系統 SHALL 等待 in-flight result
- **AND** 若 in-flight mutation 確認把裝置移到 snapshot 以外，系統 SHALL 序列化 correction `set` 回 pause coordinate
- **AND** 系統 SHALL 只在 correction success 後進入 paused
- **AND** paused 後 MUST NOT 送出舊 pending coordinate

#### Scenario: pause transaction 結果不確定

- **WHEN** in-flight mutation 或 pause correction timeout、失敗或結果不確定
- **THEN** 系統 SHALL 進入 `interrupted(positionUnknown)`
- **AND** 系統 MUST NOT 顯示 paused

#### Scenario: 約一秒 update scheduling

- **GIVEN** route running 且 device request 正常完成
- **WHEN** controllable monotonic clock 前進數秒
- **THEN** 系統 SHALL 約每秒產生一次位置更新
- **AND** paused、completed 或 interrupted 狀態 SHALL 不產生 route update

<!-- @trace
source: add-macos-location-simulator
updated: 2026-07-27
code:
tests:
-->

### Requirement: 單程完成與往返循環

未啟用 `往返循環` 時，route SHALL 由 A 移動至 B，抵達後停止更新並維持 B。啟用時，route SHALL 在 A 與 B 之間沿同一條 polyline 持續往返，直到使用者停止模擬。

#### Scenario: 單程抵達 B

- **GIVEN** `往返循環` 未啟用
- **WHEN** route progress 抵達總距離
- **THEN** 系統 SHALL 設定 B 為最後位置並進入 completed
- **AND** 系統 MUST NOT 自動 clear location

#### Scenario: 往返跨越 B

- **GIVEN** `往返循環` 已啟用且目前方向為 A → B
- **WHEN** tick distance 到達或超過 B
- **THEN** 系統 SHALL 保留超過端點的 overflow distance
- **AND** 系統 SHALL 沿同一 polyline 反向朝 A 前進
- **AND** 系統 MUST NOT 在端點 clear DVT session

#### Scenario: 往返持續執行

- **GIVEN** `往返循環` 已啟用
- **WHEN** route 多次抵達 A 或 B
- **THEN** 系統 SHALL 持續切換方向
- **AND** 系統 SHALL 直到使用者停止、App 退出或 device session interrupted 才停止

<!-- @trace
source: add-macos-location-simulator
updated: 2026-07-27
code:
tests:
-->

### Requirement: 模擬模式互斥與安全取代

point 與 route SHALL 是互斥模式。開始新模式時系統 SHALL 先停止舊位置 producer，序列化 replacement，並以新的 `SimulationSessionID` 隔離結果。

#### Scenario: 從 route 切換到單點

- **GIVEN** route session running、paused 或 completed
- **WHEN** 使用者確認新的單點位置
- **THEN** 系統 SHALL 先停止 route tick
- **AND** 系統 SHALL 設定新 point coordinate
- **AND** 舊 route callback MUST NOT 改寫 point active 狀態

#### Scenario: route 取代為單點時第一個 mutation 失敗

- **GIVEN** route producer 已停止
- **WHEN** 新 point 的第一個 device mutation 失敗或結果不確定
- **THEN** 系統 SHALL 進入 `interrupted(positionUnknown)`
- **AND** 系統 SHALL 保留舊 device ownership 供 clear 或 retry
- **AND** 系統 MUST NOT 顯示 idle 或 point active

#### Scenario: 從單點開始路線

- **GIVEN** point simulation active
- **WHEN** 使用者確認 A/B route
- **THEN** 系統 SHALL 以新的 route session 取代 point session
- **AND** 系統 SHALL 從 A 開始 route progress

#### Scenario: 單點取代為 route 時 A mutation 失敗

- **GIVEN** point simulation active
- **WHEN** 新 route 將裝置設定到 A 的 mutation 失敗或結果不確定
- **THEN** 系統 SHALL 進入 `interrupted(positionUnknown)`
- **AND** 系統 SHALL 保留 current device ownership 供 clear 或 retry
- **AND** 系統 MUST NOT 顯示 route running

<!-- @trace
source: add-macos-location-simulator
updated: 2026-07-27
code:
tests:
-->

### Requirement: 停止模擬與 clear 確認

「停止模擬」SHALL 停止 active producer 並要求 device adapter clear location。只有 clear success 後系統才 SHALL 回到 idle 並顯示已恢復真實定位。

#### Scenario: 成功停止模擬

- **GIVEN** point、running route、paused route 或 completed route active
- **WHEN** 使用者選擇「停止模擬」且 clear 成功
- **THEN** 系統 SHALL 結束 active `SimulationSessionID`
- **AND** UI SHALL 回到 idle 並顯示已恢復真實定位

#### Scenario: clear 失敗

- **WHEN** device adapter 回報 clear timeout、disconnect 或其他失敗
- **THEN** 系統 SHALL 停止 route producer並顯示 clear failure
- **AND** 系統 SHALL 提供重試
- **AND** 系統 MUST NOT 宣稱手機已恢復真實定位

<!-- @trace
source: add-macos-location-simulator
updated: 2026-07-27
code:
tests:
-->

### Requirement: 系統睡眠與裝置中斷不造成位置跳躍

系統 SHALL 僅在 macOS 即將 sleep 且 route running 時啟動與手動 pause 相同的 `pausing` transaction；只有 last confirmed coordinate 等於 pause snapshot 後才 SHALL 進入 paused。point active 或 route completed 時 MUST NOT 因 sleep notification 進入 `pausing`。device session interrupted 時系統 SHALL 停止 producer 並禁止自動 resume。

#### Scenario: Mac 在 route 執行時睡眠

- **WHEN** macOS 在 route running 時發出 sleep notification
- **THEN** 系統 SHALL snapshot 當前 confirmed coordinate／distance 並啟動與手動 pause 相同的 `pausing` transaction
- **AND** 若 sleep 前無法完成 in-flight wait 或 correction，系統 SHALL 保持 `pausing`
- **AND** wake 後系統 SHALL 完成實體座標確認才進入 paused
- **AND** 若 in-flight 或 correction 結果不確定，系統 SHALL 進入 `interrupted(positionUnknown)`
- **AND** 睡眠經過時間 MUST NOT 轉換成 route distance

#### Scenario: 非 running 模式收到 sleep notification

- **GIVEN** point simulation active 或 route completed
- **WHEN** macOS 發出 sleep notification
- **THEN** 系統 MUST NOT 進入 `pausing`
- **AND** 系統 SHALL 維持既有模擬座標與狀態

#### Scenario: 裝置中斷

- **WHEN** active simulation 收到 device session interrupted
- **THEN** 系統 SHALL 停止新的位置更新並顯示帶有 typed reason 與 position knowledge payload 的 interrupted
- **AND** 系統 MUST NOT 在重新連線後自動 resume

#### Scenario: 執行中 set timeout 或 helper／tunnel 結束

- **WHEN** active route 或 point session 遇到 `set` timeout、DVT helper exit、tunnel death 或不確定 completion
- **THEN** 系統 SHALL 立即停止 producer並進入 `interrupted(positionUnknown)`
- **AND** UI MUST NOT 繼續顯示 running 或 active
- **AND** 系統 SHALL 提供對 current device ownership 的 reconnect／clear 或 retry 路徑

<!-- @trace
source: add-macos-location-simulator
updated: 2026-07-27
code:
tests:
-->

### Requirement: 第三方服務條款風險提醒

系統 SHALL 在首次使用及每次開始模擬前顯示定位偽造可能違反第三方服務條款並導致帳號處分的提醒，且 MUST NOT 宣稱此工具不可偵測、能規避反作弊或保證帳號安全。

#### Scenario: 首次進入功能

- **WHEN** 使用者首次開啟定位模擬功能
- **THEN** 系統 SHALL 顯示用途與第三方服務條款風險提醒

#### Scenario: 開始模擬前

- **WHEN** 使用者準備確認單點或 A/B route simulation
- **THEN** 系統 SHALL 在送出第一個 device mutation 前呈現風險提醒
- **AND** 使用者取消時系統 MUST NOT 改變 iPhone 位置

<!-- @trace
source: add-macos-location-simulator
updated: 2026-07-27
code:
tests:
-->
