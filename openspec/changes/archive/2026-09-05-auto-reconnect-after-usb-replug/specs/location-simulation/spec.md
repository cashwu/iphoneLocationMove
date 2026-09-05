## ADDED Requirements

### Requirement: 未偵測 USB 中斷後的自動重新準備

當使用者動作（新的單點或路線 start、停止模擬）的 device mutation 以 typed `usbDisconnected` 失敗時，系統 SHALL 自動經由 `DeviceLocationClient.reconnect()` 執行一次 logical reconnect（新 `DeviceSessionGeneration`、重建 tunnel／DVT、clear 成功後 ready），並以新 generation 重發同一個使用者動作；每個使用者動作最多 reconnect 一次。start 的自動重備期間系統 SHALL 顯示 `reconnecting` 狀態並將控制項視為 busy，且與 `starting` 一致不持有 cleanup ownership；stop 的自動重備期間 SHALL 維持 `stopping`。自動重備 SHALL 是 single-flight：reconnect 進行中的其他 start 或 stop 要求 MUST NOT 觸發第二次 reconnect，App 退出 SHALL 等待進行中的 reconnect 結束後才清理裝置。reconnect 因同一台 iPhone 尚未插回而以 `noUSBDevice` 或 `deviceNotFound` 失敗時，系統 SHALL 以 `usbDisconnected` 作為 failure 與 reason 呈現。reconnect 或重發失敗時系統 SHALL 進入既有的 `interrupted(positionUnknown)`（start）或保留 `stopping` cleanup ownership（stop），MUST NOT 宣稱位置已套用或已恢復真實定位。此自動重備只由使用者動作觸發：active route 執行中的 producer mutation 遇到 `usbDisconnected` 時 SHALL 進入 `interrupted(positionUnknown)`，MUST NOT 自動 reconnect 或 resume 舊路線。自動重備 MUST NOT 重建 `SimulationStore`、MUST NOT 改變 setup state，也 MUST NOT 重新要求 Mac 目前位置。

#### Scenario: 單點 start 自動重備後成功

- **GIVEN** iPhone 曾在閒置時被拔除再插回，系統尚未觀察到 USB 中斷
- **WHEN** 使用者確認單點定位，且第一筆 set 以 `usbDisconnected` 失敗
- **THEN** 系統 SHALL 進入 `reconnecting(mode: point)` 並呼叫 `reconnect()` 恰好一次
- **AND** reconnect 成功後系統 SHALL 以新 generation 重發同一座標的 set 一次
- **AND** set 成功後 UI SHALL 顯示 point active，且整個過程 MUST NOT 顯示 interrupted

##### Example: 重插後按開始路線一次成功

- 手機在閒置時被拔掉再插回。使用者選「新田登山步道」按「開始路線」。
- 側欄顯示「正在重新準備裝置…」，約 8 秒後路線從第一個點開始跑，畫面沒有紅字。
- 若這時手機其實沒插回，reconnect 以 `noUSBDevice` 結束，側欄顯示「模擬已中斷」與「USB 已中斷」的指引，不宣稱手機位置已恢復。

#### Scenario: 路線 start 自動重備後成功

- **WHEN** 使用者開始路線，且 A 點的第一筆 set 以 `usbDisconnected` 失敗
- **THEN** 系統 SHALL 進入 `reconnecting(mode: route)` 並呼叫 `reconnect()` 恰好一次
- **AND** reconnect 成功後系統 SHALL 以新 generation 重發 A 點 set
- **AND** set 成功後 route SHALL 以同一 `SimulationSessionID` 從 A 開始 running

#### Scenario: reconnect 失敗

- **WHEN** start 的自動重備中 `reconnect()` 以 typed failure 結束
- **THEN** 系統 SHALL 進入 `interrupted(positionUnknown)`，failure 為該 typed failure
- **AND** 該 failure 為 `noUSBDevice` 或 `deviceNotFound` 時，系統 SHALL 改以 `usbDisconnected` 作為 failure 與 reason，UI 顯示「USB 已中斷」
- **AND** 系統 MUST NOT 重發 set，也 MUST NOT 顯示 point active 或 running

#### Scenario: reconnect 進行中的其他要求與退出

- **GIVEN** start 或 stop 的自動重備正在等待 `reconnect()`
- **WHEN** 使用者再次要求 start、stop，或要求退出 App
- **THEN** 系統 MUST NOT 觸發第二次 reconnect，也 MUST NOT 改變進行中動作的 state
- **AND** 退出流程 SHALL 等待進行中的 reconnect 與其後續 clear 結束後才對裝置執行 quit teardown

#### Scenario: 重發後再次 USB 中斷

- **WHEN** reconnect 成功後重發的 set 再次以 `usbDisconnected` 失敗
- **THEN** 系統 SHALL 進入 `interrupted(positionUnknown)`
- **AND** `reconnect()` 的呼叫次數 SHALL 仍為一次

#### Scenario: 停止模擬時自動重備並完成 clear

- **GIVEN** active simulation 的 clear 以 `usbDisconnected` 失敗
- **WHEN** 系統自動呼叫 `reconnect()` 且成功
- **THEN** 系統 SHALL 視 reconnect 內的 clear 為 clear success，結束 active `SimulationSessionID` 並回到 idle
- **AND** 系統 MUST NOT 對新 generation 另外送出第二次 clear

#### Scenario: 停止模擬時 reconnect 失敗

- **WHEN** stop 的自動重備中 `reconnect()` 以 typed failure 結束
- **THEN** 系統 SHALL 保持 `stopping` cleanup ownership並顯示該 failure
- **AND** 使用者再次停止時系統 SHALL 再次嘗試 clear 與最多一次 reconnect

#### Scenario: 路線執行中的 USB 中斷不自動重備

- **GIVEN** route running
- **WHEN** producer 的 set 以 `usbDisconnected` 失敗
- **THEN** 系統 SHALL 停止 producer 並進入 `interrupted(positionUnknown)`
- **AND** `reconnect()` 的呼叫次數 SHALL 為零

#### Scenario: reconnecting 期間的控制項

- **WHEN** simulation state 為 `reconnecting`
- **THEN** 側欄 SHALL 顯示「正在重新準備裝置…」
- **AND** 開始與 Reset 控制項 SHALL 為 disabled
- **AND** 側欄 MUST NOT 顯示「停止模擬」按鈕
- **AND** 已確認路線位置 marker MUST NOT 顯示

#### Scenario: reconnect 結束後的側欄

- **WHEN** reconnect 成功且重發的 set 成功
- **THEN** 側欄 SHALL 顯示 point active 或路線進度，且 MUST NOT 出現模擬錯誤區
- **WHEN** reconnect 失敗
- **THEN** 側欄 SHALL 顯示「模擬已中斷」與對應 failure 的指引

## MODIFIED Requirements

### Requirement: 可恢復 transport closure 的中斷判定

系統 SHALL將structured `transport-closed`與terminal helper／tunnel failure分開處理。對符合`device-tunnel-recovery` contract的single-in-flight mutation，系統 SHALL在one-shot recovery terminal前將completion視為recoverable pending，MUST NOT提前發布running success或`interrupted`。active `set` recovery success後 SHALL沿用既有active session，recovery failure後 SHALL依既有裝置中斷contract進入`interrupted(positionUnknown)`；`clear` recovery failure則 SHALL保留stopping／cleanup ownership與retry clear，MUST NOT回到idle。`set` timeout、local DVT helper exit、tunnel status `exited`、non-transport backend failure及無法驗證ownership的completion MUST NOT套用此例外。tunnel status `exited` SHALL 以 `usbDisconnected` 回報；只有「未偵測 USB 中斷後的自動重新準備」requirement 所定義的使用者動作（新的 start、停止模擬）可對其執行一次 logical reconnect，該 reconnect 建立新 generation 並先 clear，不是 transport replacement。

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
- **WHEN** ownership gate、transport rebuild或clear replay失敗，且失敗不是 `usbDisconnected`
- **THEN** 系統 SHALL保持stopping／cleanup ownership與retry clear
- **AND** UI MUST NOT顯示running、idle或已恢復真實定位

#### Scenario: terminal helper或tunnel failure

- **WHEN** active route或point session的 `set` 遇到 timeout、local DVT helper exit、tunnel status `exited`、non-transport backend failure或無法驗證ownership的completion
- **THEN** 系統 SHALL立即停止producer並進入`interrupted(positionUnknown)`
- **AND** 系統 MUST NOT 以 transport replacement 自動建立 tunnel，也 MUST NOT 自動 resume 該 session
- **AND** tunnel status `exited` 的 failure SHALL 為 `usbDisconnected`，之後只有使用者的 start 或停止動作可觸發一次 logical reconnect
- **AND** 停止動作的 `clear` 遇到 tunnel status `exited` 時不適用本 scenario，SHALL 依「停止模擬與 clear 確認」維持 `stopping` 並自動重備一次

### Requirement: 停止模擬與 clear 確認

「停止模擬」SHALL 停止 active producer 並要求 device adapter clear location。只有 clear success 後系統才 SHALL 回到 idle 並顯示已恢復真實定位。clear 以 `usbDisconnected` 失敗時，系統 SHALL 依「未偵測 USB 中斷後的自動重新準備」requirement 自動 reconnect 一次；reconnect 內的 clear 成功即視為本次 clear success。

#### Scenario: 成功停止模擬

- **GIVEN** point、running route、paused route 或 completed route active
- **WHEN** 使用者選擇「停止模擬」且 clear 成功
- **THEN** 系統 SHALL 結束 active `SimulationSessionID`
- **AND** UI SHALL 回到 idle 並顯示已恢復真實定位

#### Scenario: clear 失敗

- **WHEN** device adapter 回報 clear timeout 或其他非 `usbDisconnected` 失敗
- **THEN** 系統 SHALL 停止 route producer並顯示 clear failure
- **AND** 系統 SHALL 提供重試
- **AND** 系統 MUST NOT 宣稱手機已恢復真實定位

#### Scenario: clear 因 USB 中斷失敗後自動重備

- **WHEN** device adapter 對 clear 回報 `usbDisconnected`
- **THEN** 系統 SHALL 維持 `stopping` 並自動呼叫 `reconnect()` 一次
- **AND** reconnect 成功時系統 SHALL 回到 idle 並顯示已恢復真實定位
- **AND** reconnect 失敗時系統 SHALL 保持 `stopping` cleanup ownership 並提供重試

### Requirement: 模擬模式互斥與安全取代

point 與 route SHALL 是互斥模式。開始新模式時系統 SHALL 先停止舊位置 producer，序列化 replacement，並以新的 `SimulationSessionID` 隔離結果。新模式的第一個 device mutation 以 `usbDisconnected` 失敗時，系統 SHALL 依「未偵測 USB 中斷後的自動重新準備」requirement 自動 reconnect 一次並重發該 mutation；只有重發仍失敗或 reconnect 失敗時才適用下列 interrupted 條款。

#### Scenario: 從 route 切換到單點

- **GIVEN** route session running、paused 或 completed
- **WHEN** 使用者確認新的單點位置
- **THEN** 系統 SHALL 先停止 route tick
- **AND** 系統 SHALL 設定新 point coordinate
- **AND** 舊 route callback MUST NOT 改寫 point active 狀態

#### Scenario: route 取代為單點時第一個 mutation 失敗

- **GIVEN** route producer 已停止
- **WHEN** 新 point 的第一個 device mutation 失敗或結果不確定，且失敗不是可自動重備的 `usbDisconnected`，或自動重備後的重發仍失敗
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
- **WHEN** 新 route 將裝置設定到 A 的 mutation 失敗或結果不確定，且失敗不是可自動重備的 `usbDisconnected`，或自動重備後的重發仍失敗
- **THEN** 系統 SHALL 進入 `interrupted(positionUnknown)`
- **AND** 系統 SHALL 保留 current device ownership 供 clear 或 retry
- **AND** 系統 MUST NOT 顯示 route running

#### Scenario: 已中斷的舊 session 被新模式取代

- **GIVEN** 舊 point 或 route session 因 USB 中斷處於 `interrupted(positionUnknown)`
- **WHEN** 使用者確認新的單點或路線，且第一個 mutation 以 `usbDisconnected` 失敗
- **THEN** 系統 SHALL 自動 reconnect 一次（reconnect 內先 clear）並重發該 mutation
- **AND** 重發成功後 UI SHALL 顯示新 session 的 point active 或 route running

### Requirement: 單點定位模式

系統 SHALL 提供獨立的單點定位模式。只有在 device session ready 且使用者確認 preview coordinate 後，系統才 SHALL 設定 iPhone 位置，並持有該位置直到使用者停止模擬、切換至另一個已確認模式或退出 App。設定座標的第一筆 mutation 以 `usbDisconnected` 失敗時，系統 SHALL 依「未偵測 USB 中斷後的自動重新準備」requirement 自動 reconnect 一次並重發。

#### Scenario: 確認單點定位

- **GIVEN** device session ready 且已有有效 preview coordinate
- **WHEN** 使用者按下「設定位置」
- **THEN** 系統 SHALL 建立新的 `SimulationSessionID` 並設定該座標
- **AND** UI SHALL 在收到 device success 後顯示 point active

#### Scenario: 設定單點失敗

- **WHEN** device adapter 無法確認座標設定成功，且失敗不是可自動重備的 `usbDisconnected`，或自動重備後的重發仍失敗
- **THEN** 系統 SHALL 顯示 typed error 與重試動作
- **AND** 系統 MUST NOT 顯示 point active

#### Scenario: 單點維持到明確停止

- **GIVEN** point simulation active
- **WHEN** 使用者未按「停止模擬」且 App 未真正退出
- **THEN** 系統 SHALL 維持目前模擬位置

### Requirement: 工作區重置

系統 SHALL 在地圖控制欄提供「Reset」按鈕，把 Mac 端地圖工作區重置到 App 剛啟動的狀態。按下按鈕後系統 MUST 先顯示確認對話框才執行：顯示確認對話框當下模擬持有清理責任時，警語 MUST 包含 clear 語義句「只有手機回覆 clear 成功後，App 才會顯示已恢復真實定位。」；無清理責任時（含裝置未就緒的未連線模式）SHALL 使用說明會清除搜尋、A/B 端點與路線設定的輕量警語。

確認後系統 SHALL 立即重置 Mac 端工作區：清空搜尋框、搜尋結果、預覽點、A/B 端點、路線預覽與路線狀態、錯誤訊息，步行速度回到預設 4.5 km/h，往返循環回到關閉。所有 in-flight 的 search、reverse geocode 與 directions 要求 MUST 被取消，且其回應 MUST 以 generation 判定為 stale 而不得套用；generation 計數器 MUST NOT 歸零，MUST 以單調遞增方式作廢舊回應。

執行當下模擬持有清理責任時，系統 SHALL 同時發出與既有「停止模擬」相同的停止流程；clear 失敗時系統 MUST NOT 將 App 呈現為已恢復真實定位，MUST 保留既有的失敗顯示與清理重試入口，且 Mac 端工作區重置不因 clear 失敗而回復。模擬處於 busy 狀態（starting、reconnecting、replacing、無失敗的 stopping）時「Reset」按鈕 SHALL 為 disabled。

重置後的地圖鏡頭：Mac 目前位置已取得時 SHALL 置中到 Mac 目前位置；尚未取得時 SHALL 重新武裝初始置中，使後續第一次取得 Mac 位置時依既有初始置中規則置中，等同 App 剛啟動。

#### Scenario: 模擬進行中重置需 clear 語義確認並停止模擬

- **GIVEN** 步行路線模擬正在進行
- **WHEN** 使用者按下「Reset」
- **THEN** 顯示含「只有手機回覆 clear 成功後，App 才會顯示已恢復真實定位。」的確認對話框
- **AND** 使用者確認後，Mac 端工作區立即重置
- **AND** 系統對模擬發出與既有「停止模擬」相同的停止流程

#### Scenario: 無模擬時重置使用輕量確認

- **GIVEN** 模擬未啟用或裝置未就緒
- **WHEN** 使用者按下「Reset」並確認
- **THEN** 確認警語為輕量版本，說明會清除搜尋、A/B 端點與路線設定
- **AND** Mac 端工作區重置，不對裝置發出任何命令

#### Scenario: 重置範圍與預設值

- **GIVEN** 使用者已搜尋地點、設定預覽點與 A/B 端點、建立路線預覽並把速度調為非預設值
- **WHEN** 使用者確認重置
- **THEN** 搜尋框、搜尋結果、預覽點、A/B 端點、路線預覽與路線狀態、錯誤訊息全部清空
- **AND** 步行速度回到 4.5 km/h，往返循環回到關閉

##### Example: 速度與往返循環回到預設

- 重置前：速度 6.0 km/h、往返循環開啟、A/B 已設定且路線可確認
- 確認重置後：速度 4.5 km/h、往返循環關閉、A/B 清空、路線狀態回到未建立

#### Scenario: in-flight 回應在重置後判定 stale

- **GIVEN** 一個 search 要求與一個 directions 要求尚未完成
- **WHEN** 使用者確認重置
- **AND** 之後舊要求的回應才到達
- **THEN** 兩個回應皆被判定 stale 而不套用
- **AND** generation 計數器未歸零，維持單調遞增

#### Scenario: clear 失敗不掩蓋且工作區維持已重置

- **GIVEN** 模擬進行中，使用者確認重置
- **WHEN** 手機端 clear 失敗
- **THEN** 模擬狀態顯示既有的清除失敗訊息與清理重試入口
- **AND** App 不呈現為已恢復真實定位
- **AND** Mac 端工作區維持已重置狀態

#### Scenario: busy 狀態下 Reset disabled

- **WHEN** 模擬處於 starting、reconnecting、replacing 或無失敗的 stopping 狀態
- **THEN** 「Reset」按鈕為 disabled

#### Scenario: 重置後的鏡頭行為

- **WHEN** 使用者確認重置且 Mac 目前位置已取得
- **THEN** 地圖鏡頭置中到 Mac 目前位置
- **WHEN** 使用者確認重置且 Mac 目前位置尚未取得
- **THEN** 後續第一次取得 Mac 位置時，地圖依既有初始置中規則置中
