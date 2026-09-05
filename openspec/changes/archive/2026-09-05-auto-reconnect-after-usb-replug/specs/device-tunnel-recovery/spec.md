## MODIFIED Requirements

### Requirement: recovery terminal state 依 mutation 類型分流

active `set`的recovery、new tunnel／DVT start或mutation replay無法完成時，系統 SHALL停止route producer，並將active simulation標示為`interrupted(positionUnknown)`；系統 MUST NOT宣稱最後target已套用，也 MUST NOT自動從不確定位置繼續移動。`clear`的相同failure則 SHALL保留stopping／cleanup ownership與retry clear，MUST NOT回到idle或宣稱已恢復真實定位。當 recovery 的 status probe 回報 tunnel process `exited` 時，adapter SHALL 視同觀察到 USB 中斷：SHALL 釋放 stale lease 與 session、使 recovery ownership 失效、記錄 disconnected device、將 device session state 轉為 `interrupted(positionUnknown)`，並回傳 typed `usbDisconnected`；MUST NOT 回傳 generic `tunnelFailure`，也 MUST NOT 把該 failure 映射為 `staleGeneration`。此 USB 中斷語意 MUST NOT 觸發 transport recovery；同一裝置的後續重建只能經由 logical reconnect（新 `DeviceSessionGeneration`、clear 成功後 ready）。

#### Scenario: USB 已不可用

- **GIVEN** transport failure後同一台 iPhone已不再可透過USB建立 tunnel
- **WHEN** recovery start失敗
- **THEN** route SHALL 進入 `interrupted(positionUnknown)`
- **AND** UI SHALL 提供 typed reconnect／重新準備動作
- **AND** 失敗為 `usbDisconnected` 時，後續處置依 location-simulation「未偵測 USB 中斷後的自動重新準備」，由使用者的 start 或停止動作觸發 logical reconnect

#### Scenario: recovery 成功

- **WHEN** recovery與原 mutation replay皆成功
- **THEN** route SHALL 保持 running並從已確認進度繼續
- **AND** UI MUST NOT 顯示 terminal interruption

#### Scenario: stop cleanup recovery失敗

- **GIVEN** active simulation仍擁有可能殘留的裝置位置
- **WHEN** clear recovery失敗
- **THEN** 系統 SHALL 保留 cleanup ownership與 retry clear動作
- **AND** UI MUST NOT 宣稱已恢復真實定位
- **AND** 失敗為 `usbDisconnected` 時，retry clear 依 location-simulation「未偵測 USB 中斷後的自動重新準備」自動 reconnect 一次

#### Scenario: tunnel status exited 視為 USB 中斷

- **GIVEN** 同一台 USB iPhone 曾被拔除再插回，但系統尚未觀察到任何 USB 中斷事件
- **WHEN** `set` 或 `clear` 因 structured `transport-closed` 進入 recovery，且 status probe 回報 tunnel process `exited`
- **THEN** adapter SHALL 記錄 `transport.recovery_failed`，並以 `usbDisconnected` 結束該 mutation
- **AND** device session state SHALL 為 `interrupted(positionUnknown)`，reason 為 `usbDisconnected`
- **AND** adapter SHALL 清除 stale tunnel lease、DVT handle 與 session，並記錄該裝置為 disconnected device
- **AND** diagnostic log SHALL 記錄 `usb.disconnected` 且 `source` 為 `tunnel_exited`
- **AND** adapter MUST NOT 對已 `exited` 的 lease 呼叫 `stopTunnel`，也 MUST NOT 啟動 replacement tunnel

#### Scenario: exited 之後的 mutation 回報 USB 中斷

- **GIVEN** adapter 已因 tunnel `exited` 進入 `interrupted(positionUnknown)`
- **WHEN** 上層再次送出 `set` 或 `clear`
- **THEN** adapter SHALL 回傳 `usbDisconnected`
- **AND** adapter MUST NOT 回傳 `staleGeneration`

#### Scenario: exited 之後同一裝置 reconnect

- **GIVEN** adapter 已因 tunnel `exited` 進入 `interrupted(positionUnknown)`
- **WHEN** 上層呼叫 `reconnect()` 且同一台 iPhone 可經 USB 建立 tunnel
- **THEN** adapter SHALL 以更大的 `DeviceSessionGeneration` 依 reconcile、startTunnel、startDVT、clear 的順序重建
- **AND** adapter SHALL 只在 clear 成功後進入 ready
- **AND** 使用新 generation 的 `set` SHALL 成功
