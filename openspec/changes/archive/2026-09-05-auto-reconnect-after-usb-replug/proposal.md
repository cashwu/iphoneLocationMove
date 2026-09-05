## Summary

修正「連接 iPhone 後拔除、再插回，接著按下模擬就失敗」的問題。App 正式路徑沒有任何 USB 拔除偵測，拔線後 adapter 仍認為 session ready；重插後第一筆 mutation 觸發 transport recovery，status probe 發現舊 tunnel process 已 `exited`，recovery 依 contract 放棄並回傳 generic `tunnelFailure("Tunnel process exited before recovery")`，UI 指向錯誤的「重新核准並重試」動作，之後連「停止模擬」都因 `staleGeneration` 卡死，使用者只能重開 App。本 change 把 tunnel `exited` 視為 USB 中斷、讓新的模擬 start 與 stop 在遇到 USB 中斷時自動執行一次既有的 logical reconnect（新 generation、重建 tunnel／DVT、先 clear 再 ready）並重發同一個使用者動作，使用者按一次就能成功。不新增常駐 USB 監聽。

## Motivation

- 2026-09-05 的 diagnostic log 顯示實際序列：`point.start_requested` → `dvt.transport_closed` → `transport.recovery_started` → `tunnel.status_probed state=exited terminationStatus=0` → `transport.recovery_failed` → `location.set_failed tunnelFailure("Tunnel process exited before recovery")`，接著 `stop_requested` → `location.clear_failed staleGeneration`。整份 log 從未出現 `usb.disconnected` 事件。
- `DeviceRecoveryCoordinator.handleUSBDisconnect` 與 `PymobiledeviceAdapter.reconnect()` 已完整實作且有測試，但只在測試中被呼叫；正式 App 沒有接上任何拔線來源，所以 spec `ios-device-session` 的「USB 中斷與安全重連」在正式路徑上從未觸發。
- `device-tunnel-recovery` spec 規定 recovery MUST NOT 對 tunnel status `exited` 執行 transport recovery，這是正確的；缺的是「發現 `exited` 之後」的狀態轉移：adapter 目前保留 stale lease 與 `ready` state，也沒有記錄 disconnected device，導致後續 clear 走到 `staleGeneration`。
- `DeviceFailurePresentation` 把所有 `tunnelFailure` 呈現為「USB tunnel 失敗／重新核准並重試」，對這個情境是錯誤指引；`usbDisconnected` 的既有呈現「USB 已中斷／重新連接同一台 iPhone 後會先 clear」才是正確的。
- 使用者已確認：閒置時拔線要到下次按模擬才被發現是可接受的；但被發現之後必須能直接成功模擬，而不是顯示錯誤再要求多按兩次。

## Proposed Solution

1. **adapter 把 tunnel `exited` 視為 USB 中斷，且 reconnect 內 clear 失敗不留下半套 session**：`recoverTransport` 在 status probe 得到 `exited` 時，不再拋 generic `tunnelFailure`，而是走與 `handleUSBDisconnect` 相同的 disconnect teardown（清除 session 與 lease、advance logical generation 與 transport generation、使 recovery ownership 失效、記錄 `disconnectedDeviceID`、state 進 `interrupted(positionUnknown)`），然後回傳 typed `usbDisconnected`。之後任何 set／clear 都回傳 `usbDisconnected` 而非 `staleGeneration`，且 `reconnect()` 可重建。`reconnect()` 在 clear 階段失敗時，非 `usbDisconnected` 的失敗會拆除剛建立的 tunnel／DVT、清除 session 並保留 disconnected device 記錄，`usbDisconnected`（clear 的 recovery 探到 `exited`）則沿用中斷狀態不重複拆除；兩者都讓下一次使用者動作仍能再 reconnect 一次，不會留下第二個 lease 或 stale generation。
2. **`DeviceLocationClient` 提供 `reconnect()` seam**：把 adapter 既有的 `reconnect()` 納入 `DeviceLocationClient` protocol，讓 `SimulationStore` 可以在不認識 adapter 的前提下觸發 logical reconnect。
3. **`SimulationStore` 在 start 與 stop 路徑自動 reconnect 一次**：
   - 單點或路線的第一筆 set 因 `usbDisconnected` 失敗時，state 進入新的 `reconnecting(mode:sessionID:)`，呼叫 `reconnect()`；成功後以新的 generation 重發同一筆 start mutation，之後走既有 success／failure 路徑；reconnect 失敗或重發後再次 `usbDisconnected` 則進入 `interrupted(positionUnknown)`，每次 start 最多 reconnect 一次。reconnect 因同一台 iPhone 尚未插回而以 `noUSBDevice` 或 `deviceNotFound` 失敗時，視同 `usbDisconnected` 呈現「USB 已中斷」指引。
   - reconnect 是 single-flight：start 與 stop 共用同一個進行中動作 handle 序列化，App 退出時先等待進行中的 reconnect 再清理；`SimulationStore` 的 lifecycle extension 從 `AppLifecycleCoordinator.swift` 搬回 `SimulationStore.swift`。
   - 停止模擬的 clear 因 `usbDisconnected` 失敗時，保持 `stopping` 並呼叫 `reconnect()`；因為 reconnect 本身在 ready 前必須成功 clear，reconnect 成功即等於 clear 成功，state 回到 idle；reconnect 失敗則維持 `stopping(failure:)` 與既有的重試清除。
   - 路線執行中 producer 的 set 遇到 `usbDisconnected` 維持既有行為：進入 `interrupted(positionUnknown)`，MUST NOT 自動 reconnect 或 resume 舊路線。
4. **UI 呈現 reconnecting**：側欄在 `reconnecting` 顯示「正在重新準備裝置…」進度，該狀態視為 busy 且與 `starting` 一致不持有 cleanup ownership（Reset 與開始按鈕 disabled、不顯示「停止模擬」按鈕）。`DeviceSetupStore` 的 `ready` state 維持不變，不因 auto reconnect 重新要求 Mac 位置或重建 `SimulationStore`。

## Non-Goals

- 不新增常駐 USB 拔除監聽（usbmux listen、IOKit 或輪詢 `discoverUSBDevices`）；閒置時拔線延後到下次使用者動作才被發現。
- 不把 `DeviceRecoveryCoordinator` 接進正式 App，也不移除它。
- 不自動繼續拔線前的舊路線；路線執行中拔線仍進入 `interrupted(positionUnknown)`。
- 不改變 transport recovery 的 one-shot 規則：tunnel status `exited` 仍 MUST NOT 執行 transport recovery；本 change 的自動重備是 logical reconnect（新 generation），不是 transport replacement。
- 不新增獨立的「重新連接」按鈕；本 change 以自動 reconnect 覆蓋 start 與 stop 兩條使用者動作。
- 不修改 Python helper、privileged tunnel helper 或 XPC protocol。

## Alternatives Considered

- **新增 USB 監聽並接上 `DeviceRecoveryCoordinator`**：可以在拔線當下就顯示中斷，但需要新的常駐監聽模組（usbmux listen 或 IOKit）與新的 helper 協定或輪詢機制，屬於新 seam；使用者已確認延後偵測可接受，故不採用。
- **只把 `exited` 映射為 `usbDisconnected` 並顯示「重新連接」按鈕（方案 A）**：改動最小，但使用者按模擬會先看到紅字錯誤，再按「重新連接」與再按一次模擬，共三次操作；使用者明確選擇一次操作即成功的方案 B。
- **在 transport recovery 內對 `exited` 自動重建 tunnel 並重播 mutation**：違反 `device-tunnel-recovery` 對 `exited` 的禁止條款，且會在舊 logical generation 下重播、跳過「reconnect 前先 clear」的 contract；不採用。
- **由 `DeviceSetupStore` 重建 `SimulationStore` 並重播 start intent**：需要跨層傳遞 pending start intent、在 view 持有舊 store 時置換 store，機制更多；`SimulationStore` 自己持有可更新的 generation 更單純。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `device-tunnel-recovery`：recovery 於 status probe 發現 tunnel `exited` 時的 terminal state 改為 USB 中斷（typed `usbDisconnected`、釋放 lease、可 reconnect），並修正後續 clear 的失敗分類。
- `ios-device-session`：`reconnect()` 成為 `DeviceLocationClient` 對上層公開的 seam；未被偵測的拔線後由使用者動作觸發同一裝置重新連線。
- `location-simulation`：新增「未偵測 USB 中斷後的自動重新準備」requirement（start 與 stop 各自動 reconnect 一次、reconnecting 狀態、失敗分流、single-flight 與退出等待），在既有「可恢復 transport closure 的中斷判定」「停止模擬與 clear 確認」「模擬模式互斥與安全取代」「單點定位模式」四個 requirement 明文授權此 logical reconnect 例外，並把 `reconnecting` 加入「工作區重置」的 busy 枚舉。

## Impact

- Affected specs:
  - openspec/specs/device-tunnel-recovery/spec.md
  - openspec/specs/ios-device-session/spec.md
  - openspec/specs/location-simulation/spec.md
- Affected code:
  - New:
    - (none)
  - Modified:
    - iPhoneLocationMove/Device/PymobiledeviceAdapter.swift
    - iPhoneLocationMove/Device/DeviceLocationClient.swift
    - iPhoneLocationMove/Features/Simulation/SimulationStore.swift
    - iPhoneLocationMove/Features/Map/LocationMapView.swift
    - iPhoneLocationMove/App/AppLifecycleCoordinator.swift
    - iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift
    - iPhoneLocationMoveTests/SimulationStoreTests.swift
    - iPhoneLocationMoveTests/ContentViewTests.swift
    - iPhoneLocationMoveTests/AppShellTests.swift
    - iPhoneLocationMoveTests/DeviceSetupStoreTests.swift
    - iPhoneLocationMoveTests/DisconnectReconnectIntegrationTests.swift
  - Removed:
    - (none)
