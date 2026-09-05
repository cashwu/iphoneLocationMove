## Context

`PymobiledeviceAdapter` 以 logical `DeviceSessionGeneration` 綁定一個 prepared session，並以獨立的 `DeviceTransportGeneration` 與 `RecoveryOwnershipEpoch` 管理 tunnel／DVT transport 的 one-shot recovery。`DeviceSetupStore.connect` 在 session ready 後建立一個持有固定 `generation` 的 `SimulationStore`，view 層透過 `SimulationStoreState` 觀察狀態；`DeviceLocationClient` 是 `SimulationStore` 對裝置的唯一 seam，`DeviceSessionPreparing` refine 了它供 `DeviceSetupStore` 使用。

USB 拔線的處理已經存在：`PymobiledeviceAdapter.handleUSBDisconnect(deviceID:)` 把 state 轉成 `interrupted(positionUnknown)` 並記錄 `disconnectedDeviceID`，`PymobiledeviceAdapter.reconnect()` 以新 generation 重新 prepare、先 clear 成功才進 ready。但正式 App 沒有任何拔線來源呼叫這兩個方法（`DeviceRecoveryCoordinator` 只在測試中被建構），diagnostic log 也從未出現 `usb.disconnected`。

因此重插後的第一筆 mutation 走 `recoverTransport`：`shutdownDVT` 之後 status probe 回報 `exited`，transaction 依 contract 放棄，但只拋出 generic `DeviceLocationError.tunnelFailure("Tunnel process exited before recovery")`，adapter 仍持有 stale `tunnelLease` 與 `session`、state 仍為 `ready`。接下來的 `clearLocation` 走同一條路徑後在 catch 內被映射成 `staleGeneration`，`SimulationStore.stop` 卡在 `stopping(failure:)`。UI 端 `DeviceFailurePresentation` 對 `tunnelFailure` 一律回「重新核准並重試」，對此情境是錯誤指引；`usbDisconnected` 的既有呈現才正確。

使用者已確認兩點：閒置時拔線延後到下次按模擬才被發現可以接受；被發現後必須一次操作就成功，不能先出紅字再要求多按兩次。

## Goals / Non-Goals

**Goals**

- adapter 在 status probe 發現 tunnel `exited` 時，等同於觀察到 USB 中斷：釋放 stale 資源、記錄 disconnected device、state 進 `interrupted(positionUnknown)`、回傳 typed `usbDisconnected`，之後任何 set／clear 都回 `usbDisconnected` 而非 `staleGeneration`。
- `reconnect()` 的每一種失敗都讓 adapter 回到「可再次 reconnect」的狀態：不留下新 generation 的半套 session，也不留下第二個 tunnel lease。
- `SimulationStore` 在「使用者動作」（新的單點／路線 start、停止模擬）遇到 `usbDisconnected` 時，自動執行一次既有的 logical `reconnect()`，成功後以新 generation 重發同一動作；失敗才進入既有的 interrupted／stopping failure 狀態。reconnect 是 single-flight，App 退出會等待它結束。
- UI 在自動重備期間顯示「正在重新準備裝置…」，控制項維持 busy，不顯示「停止模擬」。
- 路線執行中的 producer 失敗維持既有 `interrupted(positionUnknown)`，不自動 reconnect、不自動 resume。

**Non-Goals**

- 不新增 usbmux／IOKit 監聽或輪詢；不把 `DeviceRecoveryCoordinator` 接進正式 App。
- 不改變 transport recovery 對 `exited` 的禁止條款；logical reconnect 不是 transport replacement。
- 不重建 `SimulationStore`、不改變 `DeviceSetupStore` 的 state、不因自動重備重新要求 Mac 位置。
- 不修改 Python helper、privileged tunnel helper、XPC protocol、`DeviceFailurePresentation` 的文案。

## Decisions

### 1. tunnel `exited` 在 adapter 內映射為 USB 中斷

把 `handleUSBDisconnect(deviceID:)` 中「同步標記中斷」的部分抽成 private `markUSBDisconnected(oldSession:source:)`：遞增 `RecoveryOwnershipEpoch`、遞增 logical `generation`、`session = nil`、`disconnectedDeviceID = oldSession.device.id`、`state = .interrupted(session: oldSession, interruption: DeviceInterruption(reason: .usbDisconnected, positionKnowledge: .unknown))`、`tunnelLease = nil`、`dvtHandle = nil`、`runtime = nil`、遞增 `transportGeneration`，並記錄 `usb.disconnected` 事件，metadata 增加 `source`（`external` 或 `tunnel_exited`）。`handleUSBDisconnect` 在呼叫它之前先 capture `oldSession.generation` 與目前的 `tunnelLease`，呼叫後再以 captured 值執行既有的非同步 `try? shutdownDVT`／`try? stopTunnel` 清理（mark 之後 `tunnelLease` 已為 nil，不能再從屬性讀取）。

`recoverTransport` 的 status probe 分支改為：`status.state == .exited` 時（DVT 已在步驟 2 shutdown，helper 依 contract 已移除該 lease ownership，因此不再對該 lease 呼叫 `stopTunnel`）呼叫 `markUSBDisconnected(oldSession: expectedSession, source: .tunnelExited)`，然後直接拋出 `DeviceLocationError.usbDisconnected`；此分支不自行記錄 `transport.recovery_failed`，由既有 catch 區塊記錄恰好一次。`recoveryMetadata` 的 `logicalGeneration` 改帶 `ownership.logicalGeneration`（captured 值），避免 mark 之後讀到已遞增的即時 generation。`recoverTransport` 的 catch 區塊 MUST 對 `usbDisconnected` 原樣重拋，不得因為 epoch 已被自己遞增而套用 `staleGeneration` 映射；其他 error 的既有映射不變。`exited` 分支在 candidate lease 建立前發生，因此沒有 candidate 需清理。`activeSimulationSessionID` 保留，因為 iPhone 端位置仍不確定，直到 `reconnect()` 的 clear 成功。

效果：`clearLocation` 在 `session == nil` 時拋 `usbDisconnected`，`performSetLocation` 亦同，所以中斷後的所有 set／clear 都是 typed `usbDisconnected`；`reconnect()` 的既有前提 `disconnectedDeviceID != nil` 成立，可直接重建。既有 `PymobiledeviceAdapterTests` 中預期 `tunnelFailure("Tunnel process exited before recovery")` 的 diagnostics 案例改為預期 `usbDisconnected` 與 `interrupted` state。

### 2. `reconnect()` 成為 `DeviceLocationClient` 的 seam，且 clear 失敗不留下半套 session

`DeviceLocationClient` 新增 `func reconnect() async throws -> PreparedDeviceSession`。`PymobiledeviceAdapter.reconnect()` 已存在：無 `disconnectedDeviceID` 時拋 `usbDisconnected` 且不改變 state；成功時 generation 為新值、clear 成功後才 `ready`。

本 change 修正它的 clear 失敗分支：`prepareSession` 成功後先 capture 新 lease，`sendClear` 失敗時依 failure 分流。failure 為 `usbDisconnected`（代表 clear 的 transport recovery 探到 `exited`，Decision 1 的 `markUSBDisconnected` 已清除 session／lease 並把 state 設為 `interrupted`）時不再拆除、不覆寫 state，直接重拋；其他 failure 時 adapter SHALL 與 Decision 1 相同採「先同步標記、再非同步清理」：在第一個 `await` 前同步 capture `(lease, newSession.generation)`、`session = nil`、`tunnelLease = nil`、`dvtHandle = nil`、`runtime = nil`、遞增 `transportGeneration`、state 設為 `cleanupPending(session: newSession, failure: <clear failure>)`，保留 `disconnectedDeviceID` 與 `activeSimulationSessionID`；然後以 `try? shutdownDVT(generation:)`、`try? stopTunnel(capturedLease)` 拆除 candidate，最後重拋該 failure。兩個 await 之間重入的 set／clear 因 `session == nil` 一律得到 `usbDisconnected`。這樣下一筆 set／clear 仍回 `usbDisconnected`（session 為 nil），下一次 `reconnect()` 重跑完整 prepare 與 clear，且任何時刻最多只有一個 tunnel lease，滿足 device-tunnel-recovery「MUST NOT 平行建立第二個 tunnel lease」。`prepareSession` 在 discovery、trust、developer mode、DDI、reconcile、tunnel 或 DVT 階段失敗時本來就不寫入 session（DVT 失敗會 stop 自己的 lease），state 維持該階段的 `preparing`／`selectionRequired`，`disconnectedDeviceID` 仍在，下一次 reconnect 可重跑。

所有實作 `DeviceLocationClient` 的測試 fake 補上 `reconnect()`：`SimulationStoreTests` 的 `FakeSimulationDevice`、`ContentViewTests` 的 `ContentViewSimulationDevice` 與 `ResetTestSimulationDevice`（直接 conform），以及經由 `DeviceSessionPreparing` 間接 conform 的 `ContentViewTests` 的 `ContentViewDevice`、`AppShellTests` 的 `AppShellDevice`、`DeviceSetupStoreTests` 的 `FakeSetupDevice`，共六個。預設拋 `usbDisconnected`。測試 seam 明定如下，tasks 不得隱含引入其他 seam：

- `FakeSimulationDevice`：`reconnect()` 支援結果佇列（成功回傳指定 generation 的 `PreparedDeviceSession`、失敗拋指定 error）與 `.suspended` 行為，提供 `completeNextSuspendedReconnect(result:)` 與 `recordedReconnectCallCount()`；harness 以 `store.$state` sink 記錄 state 歷史以斷言序列。
- `ResetTestSimulationDevice`：新增 `failNextSet(_:)`、`suspendNextReconnect()`、`resumeReconnect(with:)`（成功）與 `failReconnect(_:)`，讓 hosting view 可停在 `reconnecting` 並觀察其後續。
- `AppShellTests` 的 `AppShellDevice`：新增 `failNextSet(_:)` 與 reconnect 結果佇列（`enqueueReconnectResult(_:)`，可排入成功的 `PreparedDeviceSession` 或 failure），供 setup state oracle 案例觸發並完成 auto reconnect。
- `DisconnectReconnectIntegrationTests` 的 `RecoveryBoundary`：新增 `setTunnelStatus(_:)`（可回 `exited`）與 `failNextSet(_:)`（可注入 `transportClosed`），沿用既有 `failNextClear()`；不把另一檔的 private `FakePymobiledeviceBoundary` 抽成共用，因此不新增 test source file。

不使用 protocol extension 提供預設實作，避免正式型別靜默取得錯誤行為。

### 3. `SimulationStore` 的 generation 可在 reconnect 後更新，並新增 `reconnecting` 狀態

- `SimulationStore.generation` 由 `let` 改為 `private(set) var`，只在 `device.reconnect()` 成功回傳且該使用者動作仍為 current 時更新為 `PreparedDeviceSession.generation`。current 判準依路徑不同：start 路徑此時 `activeSessionID` 尚為 nil，判準是 `state` 仍為 `.reconnecting(_, sessionID)`（single-flight 下必然成立，此檢查是防禦）；stop 路徑判準是 `activeSessionID == sessionID`。這是本 change 唯一的 identity 變更：`DeviceMutationContext`／`DeviceCleanupContext` 一律以目前的 `generation` 建立，舊 generation 的 stale 判定由 adapter 既有 guard 負責。
- `SimulationStoreState` 新增 `case reconnecting(mode: SimulationMode, sessionID: SimulationSessionID)`，只用於 start 路徑；stop 路徑沿用 `stopping(sessionID:failure: nil)` 顯示「正在清除模擬定位…」。
- **single-flight**：以 `private(set) var userActionTask: Task<Void, Never>?` 取代既有的 `commandInProgress` Bool，成為「有使用者動作進行中」的單一真相。`confirmPoint`、`startRoute`、`stop` 三個入口在 `guard userActionTask == nil else { return }` 之後，把本體交給 private `runUserAction(_ body: @escaping @MainActor () async throws -> Void) async throws`：它建立 `Task<Result<Void, Error>, Never>` 執行 body，並把 outer `Task { _ = await inner.value; self.userActionTask = nil }` 指派給 `userActionTask`——清空動作放在 outer task 內、於其完成前同步執行，因此任何 `await task.value` 的等待者恢復時必然看到 `userActionTask == nil`，`stopForQuit` 的迴圈不依賴 executor 排程順序；`runUserAction` 最後 `try await inner.value.get()` 讓 `startRoute` 的 `RouteSessionError` 原樣穿出；`confirmPoint` 與 `stop` 的 body 不拋錯。`stopForQuit()` 以 `while let task = userActionTask { await task.value }` 等到沒有任何進行中動作後才呼叫 `stop()`；`hasActiveSimulation` 在 `activeSessionID != nil` 或 `userActionTask != nil` 時為 true，因此 reconnect 進行中的退出會走確認並等待，MUST NOT 在 reconnect 未結束前呼叫 `teardownForQuit`。`SimulationLifecycleControlling` 的 `SimulationStore` extension（`hasActiveSimulation`、`cleanupFailure`、`stopForQuit`）目前位於 `AppLifecycleCoordinator.swift`，本 change 把它搬到 `SimulationStore.swift` 以存取 `userActionTask`；protocol 與 `AppLifecycleCoordinator` class 本身不變。
- start 路徑（`confirmPoint` 與 `startRoute` 共用一個 private `performInitialSet(_:sessionID:mode:)`）：第一筆 set 若拋 `usbDisconnected` 且本次 start 尚未 reconnect，state 設為 `reconnecting`，記錄 `simulation.reconnect_started`（metadata：`sessionID`、`trigger=start`），呼叫 `device.reconnect()`；成功則更新 `generation`、記錄 `simulation.reconnect_succeeded`（含新 `generation`）、state 回到 `starting`，以新 generation 重發同一座標的 set 一次；之後不論成功或失敗都走既有路徑（成功 → `pointActive`／`route` running；失敗 → `interrupted(positionUnknown)`），MUST NOT 第二次 reconnect。
- **reconnect 失敗的分類**：`reconnect()` 拋出的 failure 若為 `noUSBDevice` 或 `deviceNotFound`（同一台 iPhone 尚未插回），SimulationStore SHALL 以 `usbDisconnected` 作為 interrupted failure 與 reason，使 UI 顯示既有的「USB 已中斷」指引；其他 typed failure（`deviceLocked`、`authorizationDenied`、`prerequisiteFailed`、`tunnelFailure`、`clearFailed` 等）原樣作為 failure，reason 依既有 `interruptionReason(for:)`。記錄 `simulation.reconnect_failed` 後進入 `interrupted(positionUnknown)`。
- stop 路徑：`clearLocation` 拋 `usbDisconnected` 時 state 維持 `stopping(sessionID, failure: nil)`，記錄 `simulation.reconnect_started`（`trigger=stop`）並呼叫 `device.reconnect()`。因為 `reconnect()` 的 contract 是 clear 成功後才 ready，成功即視同 clear 成功：更新 `generation`、`routeSession.clearSucceeded()`、釋放 `activeSessionID`、state `idle`、記錄 `stopped`。失敗則依上述分類記錄 `simulation.reconnect_failed`，`routeSession.clearFailed()`，state `stopping(sessionID, failure: <分類後 failure>)`，使用者可再次停止；每次停止動作最多一次 reconnect。reconnect 回來後 SHALL 先確認 `activeSessionID == sessionID` 才寫入 generation 與 state。
- producer 路徑 `complete(update:...)` 不變：`usbDisconnected` 映射為 `.uncertain(.usbDisconnected)`，route 進 interrupted，MUST NOT 呼叫 `reconnect()`。
- `prepareForReplacement` 不變：舊 session 若已因 USB 中斷 interrupted，新 start 的第一筆 set 會拿到 `usbDisconnected` 並進入本決策的 reconnect 路徑，而 `reconnect()` 內含 clear，滿足「重新連線前先 clear」。這是對 location-simulation「模擬模式互斥與安全取代」與「單點定位模式」中「第一個 mutation 失敗 → interrupted」的明文例外，spec delta 以 MODIFIED 承接。
- `confirmedRouteMarkerCoordinate` 對 `reconnecting` 回 `nil`（位置不確定）。
- master「系統睡眠與裝置中斷不造成位置跳躍」的「執行中 set timeout 或 helper／tunnel 結束」scenario 一貫解讀為 producer 的 `set` 路徑，不涵蓋停止動作的 clear；本 change 不修改該 requirement。

### 4. view 層對 `reconnecting` 的處理

`LocationMapView` 的 simulation status 對 `reconnecting` 顯示 `ProgressView("正在重新準備裝置…")`；`simulationIsBusy` 對 `reconnecting` 回 `true`（開始、Reset 等控制項 disabled）；`simulationHasCleanupOwnership` 對 `reconnecting` 與既有 `starting` 一致回 `false`，因此不顯示「停止模擬」按鈕（此時 `activeSessionID` 為 nil，按下也只會 no-op）。`ContentViewTests` 既有的 busy／relayout 狀態矩陣加入 `reconnecting`，並在同一 hosting view 驗證 reconnect 成功後進入 running 且不出現 `sidebar-simulation-error-region`、reconnect 失敗後顯示「模擬已中斷」與「USB 已中斷」。

### 5. `DeviceSetupStore` 與 Mac 位置維持不變

自動重備不改變 `DeviceSetupStore.state`（仍為原本的 `ready(session)`，顯示裝置名稱與 iOS 版本），也不重建 `SimulationStore`、不重新 `configure` lifecycle 或 sleep handler。因此 `ContentView.readyGeneration` 不變，不會再次要求 Mac 位置。`mac-map-initial-location` 的「重新連線建立新 generation」scenario 以「setup ready generation 改變」為 WHEN 條件；本 change 在 ios-device-session delta 明訂經 client seam 的 logical reconnect MUST NOT 發布新的 setup ready generation，也 MUST NOT 觸發 Mac 位置要求，因此該 scenario 的 WHEN 不成立，與 device-tunnel-recovery 對 transport replacement 的規定一致。`DeviceSetupState.ready` 內的 generation 只作為 setup 結果，不再是 live generation；live generation 由 adapter 與 `SimulationStore` 持有。多台裝置時 `reconnect()` 會以 `selectedDeviceID` 直接選擇原裝置，不進入 `selectionRequired`。

### 6. 診斷事件

- adapter：`usb.disconnected` 增加 `source` metadata（`external`／`tunnel_exited`）；`transport.recovery_failed` 沿用且每次 recovery 恰好記錄一次。
- `SimulationStore`：新增 `simulation.reconnect_started`（`sessionID`、`trigger`）、`simulation.reconnect_succeeded`（`sessionID`、`generation`）、`simulation.reconnect_failed`（`sessionID`、`failure`）。`failure` 只記錄 `DeviceLocationError` 的 case 名稱，不含 associated value，因為 reconnect 走完整 prepare，其 message 可能來自 pymobiledevice3 摘要或 `localizedDescription`；reconnect 失敗進入 interrupted／stopping 時，隨後的 `point.start_failed`／`route.start_failed`／`stop_failed` 對該 failure 同樣只記 case 名稱。metadata 不含座標或 endpoint。

## Implementation Contract

1. `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift`：新增 private `markUSBDisconnected(oldSession:source:)`，`handleUSBDisconnect` 與 `recoverTransport` 的 `exited` 分支共用，`handleUSBDisconnect` 先 capture generation 與 lease 再 mark；`exited` 分支拋 `usbDisconnected`、不自行記錄 `transport.recovery_failed`、不對已 exited 的 lease 呼叫 `stopTunnel`；catch 對 `usbDisconnected` 原樣重拋且 `transport.recovery_failed` 恰好一次、`logicalGeneration` 用 captured 值；`reconnect()` 的 clear 失敗分支對非 `usbDisconnected` failure 先同步清除 session／lease 並設 `cleanupPending`，再以 `try?` 拆除 captured candidate，對 `usbDisconnected` 直接重拋；`usb.disconnected` 事件帶 `source`。
2. `iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift`：以 `FakePymobiledeviceBoundary` 驗證 `exited` 後 `setLocation` 拋 `usbDisconnected`、adapter state 為 `interrupted(reason usbDisconnected, positionKnowledge unknown)`、後續 `clearLocation` 拋 `usbDisconnected` 而非 `staleGeneration`、boundary 事件不含對該 lease 的 `stopTunnel`、`reconnect()` 以更大的 generation 依 reconcile → startTunnel → startDVT → clear 順序完成並進 ready、新 generation 的 `setLocation` 成功、序列化 log 含恰好一次 `transport.recovery_failed` 與 `usb.disconnected source=tunnel_exited` 且不含 raw detail、endpoint 與座標；ready 狀態直接 `reconnect()` 拋 `usbDisconnected` 且 state 仍為 `ready(session)`；`reconnect()` 內 clear 以非 `usbDisconnected` failure 失敗後 boundary 事件含對新 lease 的 `stopTunnel`、state 為 `cleanupPending`、後續 `clearLocation` 拋 `usbDisconnected`、第二次 `reconnect()` 成功且過程中同時存在的 lease 不超過一個；`reconnect()` 內 clear 的 recovery 探到 `exited` 時 state 為 `interrupted` 且不對該 lease 呼叫 `stopTunnel`。
3. `iPhoneLocationMove/Device/DeviceLocationClient.swift`：`DeviceLocationClient` 新增 `reconnect() async throws -> PreparedDeviceSession`；不新增 protocol extension 預設實作；`DeviceFailurePresentation` 不變。
4. `iPhoneLocationMoveTests/SimulationStoreTests.swift`、`iPhoneLocationMoveTests/ContentViewTests.swift`、`iPhoneLocationMoveTests/AppShellTests.swift`、`iPhoneLocationMoveTests/DeviceSetupStoreTests.swift`：Decision 2 列出的六個 fake 實作 `reconnect()`，`FakeSimulationDevice`、`ResetTestSimulationDevice` 與 `AppShellDevice` 提供 Decision 2 明定的 seam。
5. `iPhoneLocationMove/Features/Simulation/SimulationStore.swift` 與 `iPhoneLocationMove/App/AppLifecycleCoordinator.swift`：`generation` 改為 `private(set) var`；新增 `SimulationStoreState.reconnecting(mode:sessionID:)`；以 `userActionTask` 與 `runUserAction` 取代 `commandInProgress`，三個入口共用，清空由 outer task 於完成前執行；`SimulationLifecycleControlling` 的 `SimulationStore` extension 自 `AppLifecycleCoordinator.swift` 搬到 `SimulationStore.swift`，`stopForQuit()` 迴圈等待 `userActionTask`，`hasActiveSimulation` 含 `userActionTask != nil`；start 路徑以 `state` 仍為 `reconnecting` 判定 current；start 路徑共用 `performInitialSet`，對 `usbDisconnected` 最多 reconnect 一次並以新 generation 重發；stop 路徑對 `usbDisconnected` reconnect 一次、成功視同 clear 成功、回寫前確認 `activeSessionID == sessionID`；reconnect 的 `noUSBDevice`／`deviceNotFound` 映射為 `usbDisconnected`；producer 路徑不呼叫 `reconnect()`；新增三個 `simulation.reconnect_*` 事件且 `failure` 只記 case 名稱。
6. `iPhoneLocationMoveTests/SimulationStoreTests.swift`：驗證單點與路線 start 在 `usbDisconnected` 後 state 序列為 `starting` → `reconnecting` → `starting` → `pointActive`／route running（以 suspended reconnect 與 `$state` 歷史觀察）、`reconnect()` 恰好一次、第二次 set 使用新 generation；reconnect 拋 `noUSBDevice` 時 interrupted 的 failure 與 reason 為 `usbDisconnected`、拋 `deviceLocked` 時 failure 為 `deviceLocked`，兩者 set 只被呼叫一次；重發後再次 `usbDisconnected` 進 `interrupted` 且 reconnect 仍為一次；stop 遇 `usbDisconnected` 時 reconnect 成功回 `idle` 且 clear 呼叫次數為一、失敗維持 `stopping(failure:)` 並可再次停止；reconnect suspended 期間再呼叫 `stop()` 或 `confirmPoint` 不產生第二次 reconnect 也不改變 state；`stopForQuit()` 在 reconnect suspended 時等待其完成後才 clear，等待期間再 enqueue 一個 `confirmPoint` 亦會被等到；reconnect 拋 `deviceNotFound` 時 failure 與 reason 亦為 `usbDisconnected`；舊 route 因 USB 中斷 interrupted 後 `confirmPoint` 的 state 歷史含 `replacing` → `starting` → `reconnecting` → `starting` → `pointActive`、`reconnect()` 恰好一次、最終為新 `SimulationSessionID`；路線執行中 producer 的 `usbDisconnected` 進 interrupted 且 reconnect 次數為零；`reconnecting` 時 `confirmedRouteMarkerCoordinate` 為 nil；`simulation.reconnect_failed` 的 log 不含帶 endpoint 字串的 associated message。
7. `iPhoneLocationMoveTests/DisconnectReconnectIntegrationTests.swift`：擴充 `RecoveryBoundary` 後以真實 `PymobiledeviceAdapter` 與 `SimulationStore` 驗證端到端：tunnel `exited` 後確認單點 → 自動 reconnect → `pointActive`，且 `SimulationStore.generation` 等於 adapter 新 session 的 generation；以及 reconnect 內 clear 失敗 → 使用者再次停止 → 第二次 reconnect 成功回 `idle`。`iPhoneLocationMoveTests/AppShellTests.swift` 以 `ControllableMacLocationProvider` 驗證 auto reconnect 完成後 `DeviceSetupStore.state` 仍為原 `ready(session)` 且 Mac 位置 request 次數不變。
8. `iPhoneLocationMove/Features/Map/LocationMapView.swift`：simulation status 加入 `reconnecting`，`simulationIsBusy` 回 true、`simulationHasCleanupOwnership` 回 false；`iPhoneLocationMoveTests/ContentViewTests.swift` 在同一 hosting view 驗證 `reconnecting` 顯示「正在重新準備裝置…」、Reset 與開始控制項 disabled、不顯示「停止模擬」；resume reconnect 後進入 running 且不存在 `sidebar-simulation-error-region`；reconnect 失敗後顯示「模擬已中斷」與「USB 已中斷」。
9. 本 change 不新增 test source file，不修改 `iPhoneLocationMove/project.yml` 或 Xcode target membership；`DeviceSetupStore`、`DeviceRecoveryCoordinator`、`AppLifecycleCoordinator` class 與 `SimulationLifecycleControlling` protocol、helper 與 XPC protocol 不變；`AppLifecycleCoordinator.swift` 的唯一改動是移除其中的 `SimulationStore` extension。

## Risks / Trade-offs

- **閒置時拔線不會即時顯示**：接受；偵測點是下一次使用者動作，路線執行中則由 producer 的下一筆 set 在秒級內觸發既有 interrupted。
- **重備約需 8 秒**：reconnect 重跑 trust／developer mode／DDI／tunnel／DVT 與 clear；UI 以 `reconnecting` 進度說明，控制項 busy，三個入口共用的 `userActionTask` guard 確保 reconnect 期間不會有第二個使用者動作或 quit teardown 交錯。
- **reconnect 期間 iPhone 未插回**：`reconnect()` 在 USB discovery 階段以 `noUSBDevice`／`deviceNotFound` 結束，SimulationStore 映射為 `usbDisconnected`，start 進 `interrupted`、stop 維持 `stopping(failure:)`，UI 顯示「USB 已中斷」且不宣稱位置已恢復；使用者插回後再按一次即可再重備一次。
- **reconnect 內 clear 失敗**：非 `usbDisconnected` 的失敗會拆除 candidate tunnel／DVT、清空 session，adapter 顯示 `cleanupPending`；`usbDisconnected`（重備期間再次拔線）則沿用 `interrupted` 且不重複拆除；兩者下一次使用者動作再完整重備；代價是多跑一次 prepare，換取「永遠只有一個 lease、永遠不會 staleGeneration 死局」。
- **`generation` 變為可變**：只在 `reconnect()` 成功且該動作仍 current 時於 MainActor 更新；start／stop 皆受 `userActionTask` 序列化，producer 在 reconnect 期間不會運行（start 尚未 `startProducer`，stop 已取消 producer 並等待 in-flight），因此不存在以舊 generation 併發派送的視窗。
- **`DeviceSetupState.ready` 的 generation 變成 stale**：它只用於顯示與一次性 Mac 位置請求；本 change 明訂其為 setup 結果而非 live generation。
- **`exited` 以外的死因**：helper crash、iPhone 重開機等也會讓 status 為 `exited`；一律走 USB 中斷語意，reconnect 會完整重跑 prerequisites，語意仍正確（位置不確定、需先 clear）。
- **`teardownForQuit` 的既有 catch 會把 `interrupted` 覆寫為 `cleanupPending`**：屬既有行為且第二次確認退出即成功，本 change 不處理。
