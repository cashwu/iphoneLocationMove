## 1. TDD：先建立可重現的失敗測試

- [x] [P] 1.1 在 `iPhoneLocationMoveHelper/tests/test_protocol.py` 建立 failing tests，涵蓋 `ConnectionTerminatedError`、socket／route errno、causal chain、一般 backend exception與 bounded detail，證明只有明確 transport closure回傳 `transport-closed`。
- [x] [P] 1.2 在 `iPhoneLocationMoveTests/TunnelHelperContractTests.swift` 建立 failing contract tests，涵蓋 stderr持續 drain、4 KiB tail、running／exited status snapshot、termination status、exited lease移除及 stop failure不得啟動第二 tunnel。
- [x] [P] 1.3 在 `iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift` 建立failing tests，涵蓋`set`／`clear` one-shot recovery、status probe、stop-before-restart、status exited立即terminal、replay exhaustion、logical generation維持、舊transport completion失效、candidate tunnel取得lease後尚未形成完整identity、DVT handle取得後才組成完整identity、candidate replay在commit前不被current gate誤拒及commit前不得發布logical success；另將disconnect、quit、reconnect分別懸停在status、candidate tunnel ready與replay pending，並將device switch至少懸停在candidate tunnel ready，驗證獨立`RecoveryOwnershipEpoch`使舊recovery不重播、candidate無leak、old transport generation不提前替換，而switch／quit仍對正確old device完成clear或保留cleanup ownership。
- [x] [P] 1.4 在 `iPhoneLocationMoveTests/SimulationStoreTests.swift` 建立failing tests，直接驗證recovery pending期間最多一筆in-flight mutation、success保持同一`SimulationSessionID`與committed progress、set terminal failure進入`interrupted(positionUnknown)`；另驗證clear rebuild／replay failure保持stopping／cleanup ownership與retry clear，不得回idle或顯示已恢復真實定位。

## 2. 結構化錯誤與 tunnel process diagnostics

- [x] [P] 2.1 在 `iPhoneLocationMoveHelper/helper.py` 實作pure exception-chain transport classifier與2,048字元detail上限，並同步`iPhoneLocationMoveHelper/PROTOCOL.md`的`transport-closed` envelope與單次replay語意；helper response可保留bounded detail，但persistent diagnostic只允許typed safe fields，使1.1通過。
- [x] [P] 2.2 在 `iPhoneLocationMoveTunnelHelper/main.swift` 實作stderr持續drain、4 KiB bounded tail、byte count、running／exited diagnostics snapshot及exited lease回收，並同步`iPhoneLocationMove/Device/TunnelHelperXPCProtocol.h`維持既有typed status contract，使1.2通過。

## 3. Adapter recovery transaction與 route contract

- [x] 3.1 在 `iPhoneLocationMove/Device/DeviceLocationClient.swift` 定義typed transport failure、`DeviceTransportGeneration`、獨立`RecoveryOwnershipEpoch`、transaction-scoped `CandidateTransportIdentity`與tunnel diagnostics／status values；public recovery decision不得依賴localized message substring。
- [x] 3.2 在 `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift` 接上`LiveTunnelClient.status`、structured helper failure mapping與allowlisted diagnostic events，實作immutable `RecoveryOwnership`、stop-old-before-start-new、non-recursive one-shot`set`／`clear` recovery transaction；每個external await前後以recovery epoch、logical generation、device identity、old transport generation與lease gate拒絕stale side effect。新tunnel先保存pending candidate generation＋lease ID，DVT helper啟動並取得handle後才組成完整`CandidateTransportIdentity`；candidate replay只產生transaction-local result，ownership再驗證並atomic commit後才發布logical success。switch／quit先失效recovery epoch，再透過同一mutation queue對old device clear；失效transaction只清理已取得的candidate lease／helper資源，使1.3通過。
- [x] 3.3 在 `iPhoneLocationMove/Features/Simulation/SimulationStore.swift` 同步typed terminal failure mapping，維持現有single-in-flight owner；recovery success沿用route token，active `set` recovery failure完成為uncertain並進入`interrupted(positionUnknown)`，`clear` recovery failure則保持stopping／cleanup ownership與retry clear且不得回idle；不得新增第二套recovery state machine，使1.4通過。

## 4. 驗證與實體 acceptance

- [x] [P] 4.1 執行 `python3 -m unittest discover -s iPhoneLocationMoveHelper/tests -p 'test_*.py'`，確認helper protocol與既有Python tests全部通過。
- [x] [P] 4.2 執行 `swift test --package-path .cash-skills` 不適用於App；改以 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS'` 執行全部Swift tests，確認recovery、tunnel contract與既有simulation行為通過。
- [x] 4.3 以含IPv6 endpoint、port及latitude／longitude字串的injected helper detail與tunnel stderr fixture，驗證`$HOME/Library/Logs/iPhoneLocationMove/diagnostic.jsonl`只含allowlisted failure code、exception type、errno、lease state、termination status與stderr byte count，且不得含raw detail、coordinate或RSD endpoint；同時證明事件順序為`dvt.transport_closed`→`transport.recovery_started`→`tunnel.status_probed`→success或failed terminal event。
- [x] 4.4 使用一台USB iPhone執行至少5分鐘或250次連續route update acceptance；若環境可安全注入tunnel termination，再驗證同一route自動續走與完整diagnostic sequence。將實際執行項目、裝置／iOS版本、結果及未執行的注入案例明記於 `openspec/changes/recover-dropped-device-tunnel/implementation-notes.md`，不得把未執行項目宣稱為通過。
