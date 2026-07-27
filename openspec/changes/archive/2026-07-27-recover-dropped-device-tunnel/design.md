## Context

2026-07-27 的實體 iPhone 診斷紀錄顯示，route session 以 `3.0 km/h` 開始後完成 72 次、約每秒一次的 `set` request；第 73 次 request 在送出約 11 秒後，Python DTX reader 先回報 `[Errno 65] No route to host`，接著 `LocationSimulation.set_location` 以 `ConnectionTerminatedError: Connection closed` 失敗。這個順序把問題定位在 iOS 17+ RSD tunnel／DVT transport，而不是 route interpolation 或 update cadence。

現有 `PymobiledeviceAdapter` 以 `DeviceSessionGeneration` 綁定 selected device、tunnel lease 與 DVT helper，且 `SimulationStore` 維持 single-in-flight mutation。任何 helper backend failure 目前都被轉成 `DeviceLocationError.helperFailure`，route 立即進入 `interrupted(positionUnknown)`。privileged helper 雖已有 typed `status(leaseID)`，App client 沒有呼叫它；tunnel process stderr 被導向未消耗的 `Pipe`，process exit detail 也不會進入 `diagnostic.jsonl`。

本 change 保留既有 USB-only、caller-bound lease、single-in-flight、absolute coordinate mutation 與 fail-closed cleanup contract，在 adapter 內加入一次性的 transport recovery transaction。因 `set` 與 `clear` 都是絕對、idempotent 的 device mutation，同一 logical request 可在新 transport 上重播一次；若重建或重播仍失敗，外部位置仍視為 unknown。

## Goals / Non-Goals

**Goals**

- 以結構化 failure kind 區分 DVT transport closure、helper process exit 與非 transport backend failure。
- 保存足以判斷 tunnel process 是否退出、termination status 與 bounded stderr tail 的診斷證據。
- 在同一台 USB device 與同一個 logical `DeviceSessionGeneration` 內，序列化重建 tunnel／DVT transport 並重播原 mutation 一次。
- 讓 recovery success 保持既有 `SimulationSessionID` 與 route progress；active `set` recovery failure停止producer並進入`interrupted(positionUnknown)`，`clear` recovery failure則保留stopping／cleanup ownership與retry clear。
- 以 deterministic fake boundary 驗證 retry bound、transport identity、stale completion、set／clear recovery 與 failure mapping。

**Non-Goals**

- 不改用 `tunneld`、Wi-Fi transport、multi-device transport pool 或背景 daemon。
- 不自動恢復 USB disconnect、trust／Developer Mode／DDI prerequisite failure。
- 不改變 route cadence、速度、插值、pause、round-trip、map state 或 Mac Core Location。
- 不提供無限 retry、指數 backoff、跨 App launch 自動續走或「保證不中斷」承諾。

## Decisions

### 1. 將 logical device session 與可替換 transport identity 分離

`DeviceSessionGeneration`繼續表示selected USB device的logical ready session，供UI、`SimulationStore`與既有stale request gating使用。新增adapter-internal `DeviceTransportGeneration`，只表示一個具體tunnel＋DVT pair；正常首次prepare與每次成功transport replacement都取得新的transport generation。另新增獨立的`RecoveryOwnershipEpoch`，只用來取消跨`await`的recovery transaction，不代表transport identity，也不使current transport上的cleanup command變成stale。

每個一般queued DVT mutation捕捉`DeviceSessionGeneration`、current `DeviceTransportGeneration`、`DeviceRequestID`與`SimulationSessionID`；一般reply只有在logical session與transport generation都仍為current時才可成功完成。recovery先保存尚未完整的candidate generation＋lease ID；candidate DVT helper成功啟動並取得handle後，才組成transaction-scoped `CandidateTransportIdentity`（candidate generation＋lease ID＋DVT handle）。recovery replay不套用current-transport gate，而使用完整candidate identity驗證reply；candidate reply只能先完成transaction-local replay result，MUST NOT直接發布logical mutation success。只有`RecoveryOwnership`再次有效、candidate identity一致並atomically commit為current transport後，adapter才可向上層發布原logical mutationsuccess。舊transport reply、stderr callback或shutdown completion MUST NOT改寫candidate／current transport ownership。

recovery 不建立新的 logical ready session、不替換 `SimulationStore`，也不觸發 per-ready-generation 的 Mac location request。這避免暫時性 transport replacement 被誤當成 USB reconnect。

### 2. Python helper 回傳結構化 transport failure

`iPhoneLocationMoveHelper/helper.py` 將 backend exception chain 正規化為兩類：

- `transport-closed`：包含 `ConnectionTerminatedError`，以及 causal chain 中代表 socket／route closure 的 `ConnectionResetError`、`BrokenPipeError`、`EOFError` 或 `OSError` errno `ENETDOWN`、`ENETUNREACH`、`EHOSTUNREACH`、`ECONNABORTED`、`ECONNRESET`、`ENOTCONN`、`EPIPE`。
- `backend-failure`：其他 DVT backend exception。

response 仍使用既有 `error` envelope，但 `error.code` 明確為 `transport-closed` 或 `backend-failure`，並保留最多 2,048 字元的 exception type／message detail。分類函式只檢查 typed exception／errno 與 causal chain；Swift MUST NOT 以 localized UI message substring 決定 recovery。

### 3. tunnel status 回傳 bounded process diagnostics

`FoundationTunnelProcess` 同時持有 stdout endpoint handle 與 stderr handle。stderr 在 process 存活期間持續 drain 至 lock-protected、UTF-8 replacement-decoded 的 tail buffer，buffer 上限為 4 KiB；超過上限只保留最新 bytes。這既避免 child process 因 pipe backpressure 停住，也保留最近的 tunnel failure context。

`TunnelLeaseSnapshot` 增加 `diagnostics`：`terminationStatus: Int32?`、`stderrTail: String` 與 `stderrByteCount: Int`。`status(leaseID)` 對存活 process 回傳 `state: running`；對已退出 process 先建立 `state: exited` snapshot、帶 termination status／stderr tail 回覆，再移除 lease ownership。`startTunnel` reply 的 diagnostics 為 current empty／running snapshot。

App 端 `LiveTunnelClient.status` 將 snapshot 映射成 typed `DeviceTunnelStatus`。raw `stderrTail` 只供 current recovery transaction分類與即時support context使用，MUST NOT 傳給 `DiagnosticLogger.record`。persistent log只保存allowlisted `failureCode`、`exceptionType`、`errno`、state、termination status與`stderrByteCount`。`DVTProcessSession`同樣先把helper error解析成typed fields，MUST NOT把raw backend detail寫入persistent metadata。既有`DiagnosticLogger.sanitize`只負責換行與長度，不是privacy redactor，design不得依賴它移除RSD endpoint、完整request payload或座標。

### 4. 單次 transport recovery transaction

`PymobiledeviceAdapter` 只在以下條件全部成立時自動 recovery：

1. logical session 與 selected device 仍 current；
2. failure 是 structured `transport-closed`；
3. 該 logical mutation 尚未執行過 recovery；
4. failure 不是 USB disconnect、authorization、prerequisite、invalid coordinate、response mismatch 或 stale generation。

transaction建立immutable `RecoveryOwnership`，捕捉device ID、logical `DeviceSessionGeneration`、舊`DeviceTransportGeneration`、舊lease ID與`RecoveryOwnershipEpoch`。`PymobiledeviceAdapter`在USB disconnect、reconnect、device switch或quit teardown開始時，必須在第一個`await`前只遞增`RecoveryOwnershipEpoch`，使所有舊recovery ownership立即失效；此動作 MUST NOT遞增current `DeviceTransportGeneration`，因此old-device clear仍可使用正確transport identity。transaction在既有mutation queue內執行，固定順序為：

1. 記錄 `transport.recovery_started`，包含 logical request ID、舊 transport generation 與 attempt `1`。
2. 終止舊 local DVT helper，避免舊 stdout／stderr callback 繼續。
3. probe current tunnel lease status並記錄 `tunnel.status_probed`。status `exited`、local helper unexpected exit或typed `unknownLease`代表terminal helper／tunnel death，依既有`location-simulation` contract立即中斷，MUST NOT自動start new tunnel。
4. 若 lease 為 `running`，必須成功 `stopTunnel` 才能繼續；其他 stop failure 立即結束 recovery，MUST NOT同時留下兩個tunnel。
5. 使用新的idempotency key啟動同一device的tunnel，先保存pending candidate generation與lease ID；ownership gate通過後啟動candidate DVT helper，取得DVT handle時才組成完整transaction-scoped `CandidateTransportIdentity`。candidate generation在此階段尚未成為current；若完整identity建立前失敗或ownership失效，只依已取得的pending lease／helper資源做candidate cleanup。
6. 在candidate transport上以同一logical `DeviceRequestID`重播原本的絕對`set`或`clear`一次。reply只依candidate identity與captured recovery ownership驗證並保存為transaction-local result，不得套用一般current-transport reply gate。
7. replay success後再次驗證recovery ownership與candidate identity，才atomically commit candidate lease／DVT／transport generation；commit完成後才能向上層發布logical mutationsuccess並記錄`transport.recovery_succeeded`。任一驗證或replay失敗時清理candidate資源、記錄`transport.recovery_failed`並回傳typed failure。

在步驟2至7的每個external `await`前後，adapter都必須執行`validateRecoveryOwnership`。如果captured recovery epoch、device、logical generation、old transport generation或old lease不再current，transaction不得執行下一個route／point side effect；若已建立candidate lease／DVT，必須只清理candidate資源，且不得清除或覆寫較新的current session。尤其在`startTunnel`回覆後、`startDVT`前後、replay前後與commit前皆須gate。quit／disconnect／reconnect可在actor reentrancy期間插入，但一旦先行使recovery ownership失效，舊transaction MUST NOT replay stale coordinate。

device switch與quit在同步遞增`RecoveryOwnershipEpoch`後，將old-device clear排入同一`DeviceMutationQueue`，等待先前recovery觀察失效並完成candidate cleanup。clear使用仍current的old `DeviceTransportGeneration`；若舊transport已被先前recovery停止，cleanup path MAY為同一old device建立只服務clear的replacement transport，但 MUST NOT replay route／point mutation。只有clear terminal success後才能shutdown DVT、stop lease、遞增／清除transport generation，並繼續switch或quit。USB disconnect則保留既有position-unknown ownership，待同一device reconnect建立新logical session後先clear。

transaction 不遞迴呼叫一般 retry path。replayed mutation 失敗後不再 recovery，因此每個 logical mutation最多兩次 device delivery attempt（原始一次、replay 一次）。

### 5. route progress 與 position knowledge

`SimulationStore` 的 in-flight mutation 在 adapter recovery 完成前維持 unresolved，因此 scheduler 不會派送第二筆 mutation。成功 replay 使用同一 logical update token 完成；`RouteSession` 只在 success 後 commit 該距離，接著依最新 monotonic instant 產生下一筆 target，既有 route 不換 `SimulationSessionID`、不回到 A，也不重建 preview。

structured `transport-closed`在one-shot recovery完成前視為recoverable pending mutation，不適用既有「不確定completion立即interrupted」terminal path。只有recovery success才將原logical update完成為success；active `set`的recovery、ownership gate或replay失敗時，adapter回傳typed `tunnelFailure`／`helperFailure`／`transportFailure`，`SimulationStore`停止producer、將該token完成為uncertain，並進入`interrupted(positionUnknown)`。`set` timeout、local helper exit、tunnel status `exited`與非structured backend failure不進入recovery，仍立即interrupted。UI MUST NOT繼續顯示running，也 MUST NOT宣稱最後target已套用。

`clearLocation`使用相同one-shot transport rebuild能力，但terminal state與`set`不同：只有新transport上的clear success才能釋放simulation ownership；rebuild、replay或ownership gate失敗時，adapter與`SimulationStore`都保持cleanup ownership與retry clear，MUST NOT回到idle或宣稱已恢復真實定位。

### 6. 診斷事件與 acceptance

新增事件：

- `dvt.transport_closed`
- `tunnel.status_probed`
- `transport.recovery_started`
- `transport.recovery_succeeded`
- `transport.recovery_failed`

每個事件包含`requestID`、logical generation、transport generation與attempt；tunnel status event另含state、termination status與`stderrByteCount`。persistent metadata使用allowlist，raw backend detail與stderr tail不得進入`diagnostic.jsonl`。測試fixture必須刻意包含IPv6 endpoint、port與latitude／longitude字串，並斷言序列化log不含原值。

實體 acceptance 使用一台 USB iPhone，先驗證至少 5 分鐘或 250 次連續 route update；再以測試 hook 或受控終止既有 tunnel process製造一次 transport closure，確認 App重建 transport、同一 route繼續且 diagnostic sequence完整。若實體環境無法安全注入 process termination，至少執行長時間路線並將強制中斷案例留在 deterministic boundary test；不得以未執行的實體 injection 宣稱通過。

## Implementation Contract

1. `iPhoneLocationMoveHelper/helper.py` 新增 pure transport classifier；`iPhoneLocationMoveHelper/tests/test_protocol.py` 直接覆蓋 exception type、errno、causal chain 與非 transport failure；`iPhoneLocationMoveHelper/PROTOCOL.md` 列出 `transport-closed` code 與 retry semantics。
2. `iPhoneLocationMoveTunnelHelper/main.swift` 的 production process controller持續drain stderr、保留4 KiB tail與byte count，且`status`對exited process回傳一次帶diagnostics的snapshot後移除lease。`iPhoneLocationMoveTests/TunnelHelperContractTests.swift`驗證bounded tail、running／exited snapshot、移除ownership與stop failure不建立第二tunnel。
3. `iPhoneLocationMove/Device/TunnelHelperXPCProtocol.h` 只沿用既有 typed `status` method，不新增任意 command；Swift Codable snapshot 增加 diagnostics fields。
4. `iPhoneLocationMove/Device/DeviceLocationClient.swift` 定義 recovery 所需 typed failure／status value；不得將 exception message substring暴露為 public recovery API。
5. `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift`新增`DeviceTransportGeneration`、獨立`RecoveryOwnershipEpoch`、immutable `RecoveryOwnership`與non-recursive one-shot recovery transaction。所有DVT send、shutdown、status probe、cleanup barrier與lease replacement均由actor／mutation queue序列化，且每個external await前後執行ownership gate。
6. `iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift`以fake boundary驗證set／clear recovery success、每筆mutation最多一次recovery、stop-before-restart、status exited terminal mapping、recovery exhaustion、old transport stale completion、candidate tunnel取得lease後尚未形成完整identity、DVT handle取得後才組成完整identity、candidate replay在commit前不被current gate誤拒、commit前不得發布logical success及logical generation不變；另將disconnect、quit、reconnect分別懸停在status、candidate tunnel ready與replay pending，並至少將device switch懸停在candidate tunnel ready邊界，驗證epoch先失效、舊recovery不重播、candidate完整回收、old transport generation不提前替換，而switch／quit仍對正確old device完成clear或保留cleanup ownership。
7. `iPhoneLocationMove/Features/Simulation/SimulationStore.swift`僅同步typed failure mapping與diagnostics所需狀態；不得另建第二個recovery state machine。`iPhoneLocationMoveTests/SimulationStoreTests.swift`驗證recovery期間無第二個in-flight update、success保持session／progress、set recovery exhaustion進入`interrupted(positionUnknown)`；clear rebuild／replay failure則保持stopping／cleanup ownership、retry clear可用且不得回idle。
8. 所有新測試須加入既有 targets；本 change不新增 test source file，因此不修改 Xcode target membership。

## Risks / Trade-offs

- **重播前一筆 `set` 可能覆寫 failure期間 iPhone 已套用的相同座標**：mutation 是絕對座標且 replay相同值，結果 idempotent；不重播不同 pending coordinate。
- **舊 tunnel stop failure可能阻止 recovery**：為避免雙 tunnel與 route ownership混亂，選擇 fail closed並中斷 route，而不是平行啟動新 lease。
- **transport classifier可能漏掉新的 exception type**：只對明確 typed closure自動 recovery；未知 exception維持既有 interrupted行為，並透過 bounded detail協助後續擴充。
- **5 分鐘 acceptance不能證明長期永不失敗**：它只驗證已知約兩分鐘 failure不再重現，以及 recovery path能在受控中斷下完成；不作 uptime保證。
- **stderr tail可能含第三方 runtime文字**：限制為4 KiB且只短暫存在privileged helper／current status reply；persistent log只寫allowlisted structured fields，不保存raw tail。公開發佈前仍需重新審查privacy與support bundle政策。
