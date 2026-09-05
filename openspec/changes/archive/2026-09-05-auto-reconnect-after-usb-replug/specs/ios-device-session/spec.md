## MODIFIED Requirements

### Requirement: USB 中斷與安全重連

系統 SHALL 在 USB 中斷時停止位置 producer 並顯示 `interrupted(positionUnknown)`，其中 `positionUnknown` 是 `interrupted` 的 position knowledge payload 而非獨立 state；系統 MUST NOT 自動恢復舊模擬。相同裝置重新連線後 SHALL 建立新 generation，重新準備 tunnel／DVT，並在進入 ready 前成功執行 clear。USB 中斷的觀察來源 MAY 是外部事件，也 MAY 是 transport recovery 的 status probe 發現 tunnel process `exited`；兩者 SHALL 產生相同的 `interrupted(positionUnknown)` 與 disconnected device 記錄。`reconnect()` SHALL 是 `DeviceLocationClient` 的一部分，供上層在使用者動作時觸發同一裝置的重新連線；沒有 disconnected device 記錄時 `reconnect()` SHALL 以 `usbDisconnected` 失敗。`reconnect()` 在 clear 階段以非 `usbDisconnected` failure 失敗時 SHALL 拆除剛建立的 tunnel／DVT 並清除 session、保留 disconnected device 記錄；以 `usbDisconnected` 失敗時（clear 的 recovery 探到 tunnel `exited`）SHALL 沿用該中斷的 `interrupted` state 且不重複拆除。兩種情況下後續 mutation 仍回報 `usbDisconnected`、下一次 `reconnect()` 可完整重跑，且任何時刻 MUST NOT 同時存在兩個 tunnel lease。經 client seam 的 logical reconnect MUST NOT 發布新的 setup ready generation，也 MUST NOT 觸發 Mac 目前位置要求。

#### Scenario: 執行途中拔除 USB

- **WHEN** active point 或 route session 執行期間 USB 中斷
- **THEN** 系統 SHALL 停止送出新的位置更新
- **AND** UI SHALL 顯示無法保證裝置端已 clear 的 `interrupted(positionUnknown)` 狀態

#### Scenario: 同一裝置重新連線

- **GIVEN** device session 因 USB 中斷進入 `interrupted(positionUnknown)`
- **WHEN** 同一台 iPhone 重新以 USB 連線且 prerequisites 完成
- **THEN** 系統 SHALL 建立新 generation 並重新建立 tunnel／DVT session
- **AND** 系統 SHALL 在 clear success 後才進入 ready
- **AND** 系統 MUST NOT 自動繼續舊路線

#### Scenario: 重連後 clear 失敗

- **WHEN** 重新連線後無法確認 clear success
- **THEN** 系統 SHALL 保持非 ready 狀態並提供重試
- **AND** 系統 MUST NOT 宣稱手機已恢復真實定位
- **AND** 失敗不是 `usbDisconnected` 時，adapter SHALL 對剛建立的 lease 執行 `stopTunnel` 並 shutdown DVT，清除 session 但保留 disconnected device 記錄；失敗為 `usbDisconnected` 時（clear 的 recovery 探到 tunnel `exited`）adapter SHALL 沿用該中斷的 `interrupted` state，MUST NOT 對已 `exited` 的 lease 呼叫 `stopTunnel`
- **AND** 後續 set 或 clear SHALL 回報 `usbDisconnected` 而非 `staleGeneration`
- **AND** 下一次 `reconnect()` SHALL 完整重跑 prepare 與 clear，且過程中同時存在的 tunnel lease 不超過一個

#### Scenario: 上層經由 client seam 觸發重新連線

- **GIVEN** device session 因 USB 中斷（外部事件或 tunnel `exited`）進入 `interrupted(positionUnknown)`
- **WHEN** 上層透過 `DeviceLocationClient.reconnect()` 要求重新連線
- **THEN** 系統 SHALL 回傳帶有新 generation 的 `PreparedDeviceSession`
- **AND** 該 generation SHALL 大於中斷前的 generation
- **AND** 上層後續的 mutation SHALL 使用該新 generation
- **AND** setup ready generation MUST NOT 改變，系統 MUST NOT 因此重新要求 Mac 目前位置

#### Scenario: 沒有中斷記錄時要求重新連線

- **GIVEN** device session 未曾記錄 disconnected device
- **WHEN** 上層呼叫 `reconnect()`
- **THEN** 系統 SHALL 以 `usbDisconnected` 失敗
- **AND** 系統 MUST NOT 改變目前 device session state
