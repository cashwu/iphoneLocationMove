## Summary

修正 iPhone 步行路線執行約一至數分鐘後，因 iOS 17+ RSD tunnel 路由消失而出現 `DTX reader exiting with error: [Errno 65] No route to host`、`ConnectionTerminatedError: Connection closed`，並永久中斷模擬的問題。系統將辨識可恢復的 tunnel／DVT transport failure、保留完整診斷證據，並在同一台 USB iPhone 仍可用時重建 transport 後重播同一筆絕對座標 mutation。

## Motivation

現有診斷紀錄顯示，路線以約每秒一次的頻率連續完成 72 次定位更新後，RSD transport 先回報 `No route to host`，接著 DVT request 才以 `ConnectionTerminatedError` 失敗。這證明步行速度、路線插值與 mutation cadence 並非直接原因；實際問題是長時間 tunnel／DVT session 中途失效。

目前 App 將所有 helper backend failure 包成 `helperFailure`，停止 route producer 並顯示「重新準備」，但沒有 probe tunnel lease、記錄 tunnel process exit detail，也沒有安全的 transport 重建路徑。使用者只能重新準備裝置並重啟路線，且 diagnostic log 無法區分 tunnel process exit、RSD route 消失或 DVT helper exit。

這是一項 Bug Fix。目標是讓暫時性的 tunnel／DVT transport failure 不再直接終止正常步行路線，同時維持既有 single-in-flight、generation isolation 與 position-unknown failure semantics。

## Proposed Solution

- 將 Python helper 的 backend error 分成可辨識的 transport closure 與其他 backend failure，保留 bounded、sanitized detail，避免 Swift 端只靠 UI 字串推測。
- 在 privileged tunnel process boundary 持續 drain stderr，保存 bounded tail 與 termination status；App 在 DVT transport failure 後立即 probe current lease status，將結果寫入既有 `diagnostic.jsonl`。
- 在 `PymobiledeviceAdapter` 內加入單一 transport recovery transaction：停止失效 DVT helper、停止或回收舊 tunnel lease、建立新的 tunnel／DVT transport identity，然後只重播原本那筆絕對 `set` 或 `clear` mutation 一次。
- recovery transaction 與既有 mutation queue 共用序列化邊界；每個 external `await` 前後重新驗證 captured logical generation、device identity 與 transport ownership，同一時間仍最多一筆 device mutation，舊 transport completion 不得穿越新 identity，也不得形成無限 retry。
- persistent diagnostic 只寫入 allowlisted structured fields，例如 failure code、exception type、errno、lease state、termination status 與 stderr byte count；raw exception message、stderr tail、RSD endpoint與座標不得寫入 `diagnostic.jsonl`。
- recovery success 對既有 route session 透明，route 由最後確認進度繼續；active `set` recovery failure停止producer並進入`interrupted(positionUnknown)`，`clear` recovery failure則保留stopping／cleanup ownership與retry clear，兩者都顯示typed tunnel／helper error。
- 增加 deterministic unit／contract tests，涵蓋 tunnel process exit、process 仍在但 RSD route 已失效、recovery success、recovery exhaustion、stale completion與`clear` recovery；實體iPhone必做長時間acceptance，強制中斷以deterministic boundary必做，實體injection僅在可安全執行時加做。

## Non-Goals

- 不支援 Wi-Fi iPhone、同時控制多台裝置或改用常駐 `tunneld`。
- 不改變步行速度範圍、約每秒一次的更新 cadence、路線插值、暫停、往返或地圖 camera 行為。
- 不在 USB 已拔除、裝置信任失效、Developer Mode 關閉或 recovery 重試失敗時自動恢復 route。
- 不無限重試、不隱藏 position-unknown 狀態，也不宣稱所有 iOS／USB transport failure 都能自動修復。
- 不變更 Mac 目前位置 marker 或 Core Location 流程。

## Alternatives Considered

- **降低更新頻率**：log 已證明前 72 次一秒更新皆成功，且失敗源頭為 RSD route 消失；降低 cadence 只會延後暴露斷線，不能修復 transport。
- **DVT 失敗後立即停止並要求使用者重開 App**：維持目前行為但可用性差，也無法使用已存在的 tunnel lease status contract 定位原因。
- **只重送 DVT request、不重建 tunnel**：`No route to host` 表示既有 RSD path 已不可用，同一連線上的重送不會恢復路由。
- **改用常駐 `pymobiledevice3 remote tunneld`**：增加新的 daemon lifecycle、權限與多裝置管理面；本次先修正既有 caller-bound lease 架構。

## Capabilities

### New Capabilities

- `device-tunnel-recovery`：在同一台 USB iPhone 的 RSD tunnel／DVT transport 中途失效時，提供結構化診斷、單次序列化重建與 idempotent mutation replay；`set`無法恢復時進入position-unknown interrupted，`clear`無法恢復時保留cleanup ownership。

### Modified Capabilities

- `location-simulation`：明確定義 structured `transport-closed` 在 one-shot recovery terminal 前屬於recoverable pending mutation；active `set` recovery success維持既有route／point session、terminal failure進入`interrupted(positionUnknown)`，`clear` terminal failure則維持stopping／cleanup ownership與retry clear。

## Impact

- Affected specs:
  - New: `openspec/specs/device-tunnel-recovery/spec.md`
  - Modified: `openspec/specs/location-simulation/spec.md`
- Affected code:
  - New:
    - (none)
  - Modified:
    - `iPhoneLocationMove/Device/DeviceLocationClient.swift`
    - `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift`
    - `iPhoneLocationMove/Features/Simulation/SimulationStore.swift`
    - `iPhoneLocationMoveHelper/helper.py`
    - `iPhoneLocationMoveHelper/PROTOCOL.md`
    - `iPhoneLocationMoveTunnelHelper/main.swift`
    - `iPhoneLocationMove/Device/TunnelHelperXPCProtocol.h`
    - `iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift`
    - `iPhoneLocationMoveTests/SimulationStoreTests.swift`
    - `iPhoneLocationMoveTests/TunnelHelperContractTests.swift`
    - `iPhoneLocationMoveHelper/tests/test_protocol.py`
  - Removed:
    - (none)
