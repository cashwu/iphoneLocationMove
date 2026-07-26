## Context

專案目前沒有 application source 或既有 capability。此 change 建立第一個 macOS target，讓使用者以原生地圖控制一台透過 USB 連接、運行 iOS 17+ 的 iPhone。iOS 17+ developer service 需要長時間 tunnel 與 DVT session；`pymobiledevice3 developer dvt simulate-location set` 會持有 session，而官方 GPX player 雖能依 timestamp 播放，卻不提供本 change 所需的可靠暫停與無限往返。

macOS UI、路線狀態與 Python／root process 的生命週期是新的跨層 seam。第一版是個人、本機、非 Mac App Store 使用，但權限邊界仍須 fail closed，且不得讓 UI 傳送任意 privileged command。

## Goals / Non-Goals

**Goals**

- 建立原生 `SwiftUI + MapKit` App，提供單點定位與 A/B 步行路線兩個互斥模式。
- 讓 route progress 由 monotonic time 與距離決定，避免 timer 漂移；支援調速、暫停、繼續、單程與往返。
- 以一個可稽核的裝置 adapter 管理 runtime、USB device、tunnel、DVT session、序列化命令、重試及清除。
- 明確表示 prerequisite、授權、連線、中斷與清除失敗，不把「已送出命令」誤報為成功。
- 讓核心路線與狀態轉移可用 deterministic clock 及 fake device client 測試。

**Non-Goals**

- Wi-Fi、並行控制多裝置、隨機位置、背景常駐 menu bar product、內建 Python runtime 或公開發佈包裝。
- 與其他 repository 共用程式碼或資料。
- 遊戲自動操作、反偵測或規避第三方服務處分。

## Decisions

### 1. 原生 app 與 seam location

`iPhoneLocationMove/` 使用 SwiftUI，地圖、搜尋及 directions 使用 MapKit。`SimulationStore` 是 UI 的單一 feature owner；它協調 `RouteSession` 與 `DeviceLocationClient`，但不解析 process output。

裝置邊界放在 `iPhoneLocationMove/Device/DeviceLocationClient.swift`，production implementation 為 actor `PymobiledeviceAdapter`。此 path 只有一個 adapter；Python helper、runtime manager 與 privileged tunnel helper 都是 adapter 內部機制，不再疊一層轉呼叫 adapter。

刪除 `PymobiledeviceAdapter` 會移除 runtime 準備、USB discovery、tunnel、DVT session、set／clear、重試與清理，App 只剩地圖預覽，因此此 seam 隱藏了實際行為而非 pass-through。

### 2. 兩種模擬模式互斥

`SimulationStore` 同一時間最多持有一個 active `SimulationSessionID`：

- `point`：確認後設定單一座標並持有。
- `route`：確認 A、B 與 MapKit pedestrian route 後逐點更新。

開始另一個模式前必須停止目前 producer，等 adapter 完成 mode replacement 後才啟動新 session。所有 async result 都帶 `SimulationSessionID`；舊 session 的 timer、helper output 或 completion 不得改寫新 session UI。

### 3. RouteSession state machine

`RouteSession` 的 normative transition table 如下；未列出的 transition 一律拒絕：

| From | Event／guard | To | Required action |
|---|---|---|---|
| `idle` | 建立有效且 immutable 的 route preview | `preview` | 保存 A、B、polyline、distance 與 ETA |
| `preview` | 使用者取消或 endpoints 失效 | `idle` | 丟棄 preview，不送出 device mutation |
| `preview` | 風險確認完成且設定 A 的第一個 mutation success | `running` | 建立 `SimulationSessionID` 與 monotonic baseline |
| `preview` | 設定 A 的第一個 mutation 失敗或結果不確定 | `interrupted` | 停止 producer；以 `positionUnknown` payload 保留 current ownership |
| `running` | 使用者 pause，或 running 時收到 sleep notification | `pausing` | 執行 pause transaction 與 command barrier |
| `pausing` | last confirmed coordinate 等於 pause snapshot | `paused` | 固定 confirmed distance；必要時先完成 correction |
| `pausing` | in-flight 或 correction 結果不確定 | `interrupted` | 以 `positionUnknown` payload 停止 producer |
| `paused` | 使用者 resume | `running` | 從 paused distance 建立新的 monotonic baseline |
| `running` | 未啟用往返且 B 的最後一次 `set` success | `completed` | 停止 tick 並維持 B |
| `running` | 啟用往返且跨越 A 或 B | `running` | 保留 overflow distance 並反轉方向 |
| `running`、`pausing`、`paused`、`completed` 或 `interrupted` | 使用者 stop、quit cleanup 或 retry clear | `stopping` | 停止 producer 並序列化 `clearLocation()` |
| `stopping` | `clearLocation()` success | `idle` | 結束 active ownership 並顯示已恢復真實定位 |
| `stopping` | `clearLocation()` 失敗或結果不確定 | `stopping` | 保留 ownership、呈現錯誤並允許 retry |
| `running`、`pausing`、`paused` 或 `completed` | transport failure、disconnect 或 active mutation 結果不確定 | `interrupted` | 停止 producer 並附帶對應 interruption payload |

- `preview` 保存 A、B、MapKit polyline、總距離與預估時間。
- `running` 保存方向、基準距離、基準 monotonic instant 與當前速度。
- `paused` 固定當前距離；resume 以新基準 instant 繼續。
- `completed` 只代表移動停止，仍維持終點模擬位置；它仍是 active simulation，可經 stop／quit 進入 `stopping`、經 transport failure 進入 `interrupted`，或經確認的 mode replacement 轉入新 session。
- `interrupted` 停止 tick 且禁止自動 resume；它帶有 typed interruption reason 與 position knowledge payload。本文的 `interrupted(positionUnknown)` 表示 state 仍是 `interrupted`，但 payload 明確記錄無法保證裝置端座標；它不是另一個 state。需裝置重新 ready 並由使用者重新開始。
- `stopping` 等待 `clearLocation()` 的確認結果。只有 clear 成功才回到 `idle`；失敗則呈現可重試錯誤。

mode replacement 由 `SimulationStore` 擁有，不是同一個 `RouteSession` 的 transition：current producer 通過 mutation barrier 終止後，store 才以新的 `SimulationSessionID` 建立 point state 或新的 route session。

任何 active-session `set` timeout、DVT helper exit、tunnel death 或不確定 completion 都會停止 producer 並進入 `interrupted(positionUnknown)`；UI 不得繼續顯示 running／active。恢復只能經由同一裝置的 reconnect／reprepare 後 clear，或由使用者對 current ownership 重試 clear。mode replacement 的第一個 mutation 失敗也進入 `interrupted(positionUnknown)`，保留舊 device ownership，不回到 idle，也不宣稱新模式 active。

### 4. 路線距離、tick 與速度

MapKit pedestrian route 的 polyline 會預先轉成帶 cumulative distance 的 segments。每次 tick 用 monotonic elapsed time × speed 算出目標距離，再以 `MKMapPoint` 在對應 segment 內插；不以「每 tick 累加固定距離」計算進度。

- 預設速度為 `4.5 km/h`，合法範圍為 `1–7 km/h`。
- UI 約每秒送出一次位置；timer 延遲時以實際 monotonic elapsed time 校正。
- `SimulationStore` 以 `RouteUpdateEpoch` 管理 update scheduler：同時最多一個 route `set` request in flight；tick burst 只保留 current epoch 的最新 pending coordinate，不排隊保存中間座標。
- pause 與 sleep pause 是完整 transaction：先進入 `pausing`、遞增 `RouteUpdateEpoch`、清除 pending coordinate，並保存 last-confirmed pause coordinate／distance；接著等待 in-flight mutation。若 last confirmed coordinate 已等於 pause snapshot，不需要額外 device mutation 即可進入 `paused`；若 in-flight mutation 確認把裝置移到 snapshot 以外，系統必須序列化一次 correction `set` 回 pause coordinate，收到 success 後才進入 `paused`。若 in-flight 或 correction 結果不確定，進入 `interrupted(positionUnknown)`，不得顯示 paused。
- speed rebase 會先使舊 epoch 失效、清除 pending coordinate 並等待 in-flight 結果；成功後以 barrier 完成時的 latest confirmed distance 建立新 baseline。未確認的 tick target 不得發布為 committed progress；若 in-flight success 推進了 confirmed distance，就沿用該距離，不得送出向後 correction。若結果不確定，進入 `interrupted(positionUnknown)`。mode replacement、stop 與 clear 則停止 producer、清除 pending，等待 current mutation barrier 完成或以 helper/session replacement 使其失效，再序列化下一個 mutation。舊 epoch completion 不得套用 UI state，clear 後不得再送出舊座標。
- 變更速度後以最新 confirmed distance 與新的 monotonic instant 繼續；running 與 paused 的 committed progress 都不得倒退或跳躍。
- 單程抵達 B 後進入 `completed` 並停留在 B。
- 往返模式用總距離的往返週期映射 elapsed distance；跨越端點時保留 overflow 並反向，不清除 DVT session。
- macOS 即將 sleep 且 route 為 `running` 時，啟動與手動 pause 相同的 `pausing` transaction。若進入 sleep 前尚未完成 in-flight wait／correction，狀態保持 `pausing`；wake 後完成座標確認才進入 `paused`，結果不確定則進入 `interrupted(positionUnknown)`。睡眠經過時間不得轉成位置距離。point active 或 route `completed` 不進入 `pausing`，並維持其既有模擬座標與狀態。

### 5. Runtime 與 helper

`RuntimeManager` 先以 capability probe 尋找相容的既有 `pymobiledevice3`，至少驗證 USB discovery、`lockdown start-tunnel --script-mode` 與 DVT simulate-location `--rsd` 能力，不只比較版號。

若找不到相容安裝且已有 Python `>=3.9`，使用者可明確按下安裝按鈕，在 App 專用 Application Support 目錄建立 venv 並安裝 lockfile 固定的版本。安裝提供進度、可取消與可重試；不得修改 global Python 或 Homebrew。沒有相容 Python 時只顯示安裝指引。

`iPhoneLocationMoveHelper/` 是長時間、unprivileged Python process。它使用 newline-delimited JSON stdin/stdout contract，持有 DVT session，接受 `set`, `clear`, `ping`, `shutdown`，並回傳帶 request ID 的 success/error event。未知 command、無效座標或 malformed JSON 必須拒絕，不得 crash 或執行 shell。

### 6. Privileged tunnel 最小化

`iPhoneLocationMoveTunnelHelper/` 是透過 `SMAppService` 註冊的 privileged helper，只提供 `startTunnel(deviceID, idempotencyKey)`, `stopTunnel(leaseID)`、`status(leaseID)` 與 `reconcile()`。它不得接受 shell 字串、任意 flags、Python path、package path 或任意 output path。

privileged runtime payload 由 signed App bundle 內的 offline wheelhouse 提供；預期 digest table 編譯在 signed privileged helper executable 內，MUST NOT 從 caller path 或外部 manifest 載入。helper 從 XPC audit token 解析 caller code URL，先以 Security framework 驗證 App designated requirement、Team ID 與完整 code signature，且 caller requirement 必須與 helper 編譯時固定值相符，才可讀取該 bundle payload。payload 與外部 manifest 同時替換、重新 ad-hoc signing、Team ID mismatch 或 invalid signature 均 fail closed。

runtime 使用 root-owned、不可由一般使用者修改且 Python `>=3.9` 的 interpreter 建立。安裝流程 MUST 以 `O_NOFOLLOW`／等價機制拒絕 symlink，依 helper 內嵌 digest table 逐檔驗證，複製到 root-owned temporary directory，重新驗證 owner／mode／digest 後以 atomic rename publish。root process MUST NOT 執行網路 `pip`、user-writable interpreter、package、manifest 或 staging payload。每次 tunnel 啟動前重新驗證 runtime root ownership、不可群組／全域寫入、無 symlink 與 payload digest；任何 mismatch 都 fail closed。

helper 以 caller audit identity、device ID 與 idempotency key 建立唯一 `TunnelLeaseID`。同一 caller／device 的重複 start 回傳既有 lease；start reply 遺失可用相同 key reconcile。XPC invalidation、owner death、App crash 或 explicit stop 都回收 lease 與 root tunnel process。App 啟動時呼叫 `reconcile()` 清理不屬於 current signed caller session 的遺留 lease。RSD endpoint 透過受型別約束的 XPC reply 回傳。拒絕授權、endpoint parse 失敗、process 提前退出或 stop 失敗都要回傳結構化錯誤。

這個 root-owned tunnel runtime 不等同公開發佈版的內建 Python runtime；它只服務必要的 privileged tunnel，公開發佈前仍須完成簽署、公證、第三方授權與更新策略評估。

### 7. Device session 與 reconnect

`PymobiledeviceAdapter` actor 序列化所有 mutating operation，並以遞增的 `DeviceSessionGeneration` 標記 connect/reconnect。來自舊 generation 的 helper 或 tunnel callback 一律忽略。

準備順序固定為 runtime probe → USB discovery／device selection → trust 與 Developer Mode 檢查 → DDI mount → tunnel → DVT helper ready。任何階段失敗都停在具體狀態並提供對應修復資訊，不得跳過 prerequisite。

USB 中斷會取消 route tick、關閉可控的 local session 並進入 `interrupted(positionUnknown)`。同一裝置重新連線後先建立新 generation 與 tunnel，再執行 `clearLocation()`；只有收到 clear success 才進入 ready，且不自動恢復舊路線。

selected device 以 UDID 綁定 generation、DVT helper、tunnel lease 與 cleanup ownership。ready 或 active 時要求改選裝置，必須先對舊 UDID 依序停止 producer、clear、shutdown helper、stop lease；全部完成後才 commit 新 selection。舊裝置 clear 失敗時不得切換，且保留舊 ownership 與重試動作。iOS 17 以下的裝置可顯示名稱與版本，但 SHALL 標記為 unsupported 並阻止 tunnel／DVT preparation。

### 8. MapKit async request identity

地點搜尋使用遞增的 `MapSearchGeneration`，directions 使用 A／B coordinate snapshot 與 `RouteRequestGeneration`。任何取代 preview ownership 的操作，包括新 query、直接點擊地圖、清除搜尋或選擇另一個 preview source，都會先遞增 `MapSearchGeneration` 並取消可取消的舊 search；無法取消時忽略 stale response。A 變更或 B 變更同樣會使舊 directions request 失效。使用者確認開始前再次驗證 route preview 的 endpoint snapshot 等於目前 A、B。

directions outcome 分成 `routeAvailable`、`noPedestrianRoute`、`cancelled`、`transientFailure` 與 `stale`。只有 `noPedestrianRoute` 顯示確定無路線；transient failure 保留 A、B 並提供 retry。

### 9. App lifecycle 與錯誤呈現

關閉主視窗不結束 App，active session 可繼續。使用者真正 quit 時若有 active simulation，先顯示確認；確認後依序停止 route producer、clear location、shutdown DVT helper、stop tunnel。即使沒有 active simulation，quit 也必須 shutdown ready DVT helper、stop tunnel lease 並讓 privileged helper reconcile。clear 或 stop 失敗時顯示錯誤並讓使用者重試或明確選擇強制退出，不得宣稱已恢復真實位置。

首次使用與每次開始模擬前顯示第三方服務條款風險；此提醒不改變功能，但必須避免任何安全或不被偵測的保證。

## Implementation Contract

1. **Project targets**
   - `iPhoneLocationMove.xcodeproj/` SHALL 定義 macOS App、unit test 與 privileged tunnel helper targets；deployment target SHALL 為 macOS 13 或更新版本。
   - `iPhoneLocationMoveHelper/` SHALL 包含 unprivileged Python DVT helper 與其 JSON protocol 文件／fixtures。

2. **Feature ownership**
   - `iPhoneLocationMove/Features/Simulation/SimulationStore.swift` SHALL 是 UI-observable simulation state 的 owner，且 SHALL 以 `SimulationSessionID` 隔離 stale async result。
   - `iPhoneLocationMove/Domain/RouteSession.swift` SHALL 實作本文定義的 route state machine、`pausing` transaction、monotonic distance progress、speed rebase、sleep pause、round-trip mapping、`RouteUpdateEpoch` 與 single-in-flight latest-only update policy。

3. **Device boundary**
   - `iPhoneLocationMove/Device/DeviceLocationClient.swift` SHALL 定義 UI 所需的最小 typed contract，包括 typed interruption reason 與 position knowledge payload；`positionUnknown` SHALL 是 `interrupted` 的 payload 而非獨立 state。
   - `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift` SHALL 是唯一 production adapter，並以 `DeviceSessionGeneration` 序列化 runtime、device、tunnel 與 DVT lifecycle。
   - `iPhoneLocationMove/Device/RuntimeManager.swift` SHALL 執行 capability probe 與 App-managed venv 安裝；不得修改 global Python 或 Homebrew。

4. **Privilege boundary**
   - `iPhoneLocationMoveTunnelHelper/` SHALL 只接受 typed `startTunnel(deviceID, idempotencyKey)`、`stopTunnel(leaseID)`、`status(leaseID)` 與 `reconcile()` requests，且 MUST NOT 接受任意 command、argument list、interpreter path、package path、manifest path 或 output path。
   - privileged helper SHALL 以固定 designated requirement／Team ID、caller code signature 與 helper executable 內嵌 digest table 驗證 signed App bundle payload，並只執行原子安裝且每次啟動前重新驗證的 root-owned pinned tunnel runtime；所有 XPC request SHALL 驗證 caller audit identity、device ID、idempotency key 及 `TunnelLeaseID` ownership。
   - root process MUST NOT 執行網路 `pip` 或任何 user-writable interpreter、package、manifest、symlink 或 staging payload。

5. **Map behavior**
   - `iPhoneLocationMove/Features/Map/LocationMapView.swift` SHALL 支援 MapKit search、marker preview、A/B selection、pedestrian route preview、distance 與 ETA；選點本身 MUST NOT 改變 iPhone 位置。
   - search／directions result SHALL 以 `MapSearchGeneration`、`RouteRequestGeneration` 與 A／B endpoint snapshot 拒絕 stale response。

6. **Failure semantics**
   - adapter／helper failure MUST 以 typed error 抵達 UI；timeout、disconnect、authorization denial、clear failure、`positionUnknown` 與 stale generation SHALL 可區分。
   - mutating device commands SHALL 單線序列化。route update SHALL 最多一個 in flight 並 latest-only coalesce；任何未知完成事件或 stale session／generation／epoch event MUST NOT 改寫 current state。

7. **Verification**
   - `iPhoneLocationMoveTests/` SHALL 以 controllable monotonic clock 與 fake device coordinate 驗證 `900 m @ 4.5 km/h = 12 minutes`、約一秒 scheduling、single-in-flight coalescing、in-flight pause correction／uncertain failure、pause/resume、in-flight speed rebase 的 confirmed-distance baseline／uncertain failure、端點 overflow、往返、running-only sleep pause 與 stale callback suppression。
   - helper protocol tests SHALL 驗證 malformed JSON、未知 command、無效座標、request ID correlation 與 clear failure。
   - adapter tests SHALL 使用 fake process／XPC boundary 驗證 prerequisite 順序、單一 mutating command、generation replacement、device switch transaction、transport failure、disconnect cleanup 與 reconnect-before-clear。
   - privileged-helper acceptance SHALL 驗證實際 owner／mode／digest、payload 與 manifest 同時替換、invalid App signature／designated requirement／Team ID、symlink／tamper fail closed、非法 caller、idempotent start、XPC invalidation／App crash 回收與 uninstall cleanup。
   - physical-device acceptance SHALL 在一台 iOS 17+ USB iPhone 上驗證單點、單程、往返、pause、quit clear 與拔線／重連；自動化測試不得要求實體 iPhone。

## Risks / Trade-offs

- **Apple 或 `pymobiledevice3` protocol 改變**：capability probe 與 typed adapter 限制影響面；版本更新必須重新跑 physical-device acceptance。
- **Privileged helper 擴大攻擊面**：以固定 typed XPC contract、audit identity、lease ownership、offline hash-locked payload、symlink／mode／digest 驗證、atomic install、owner-death cleanup 與最小權限降低風險。公開發佈前必須另做 security、dependency licensing 與 signing review。
- **App-managed venv 安裝依賴網路與既有 Python**：提供可重試進度與明確離線／缺 Python 指引；不在第一版偷偷安裝 system dependency。
- **MapKit route 可能不存在或動態改變**：沒有 pedestrian route 時禁止開始並保留 A、B 供修改；active session 使用已確認的 immutable polyline，不在途中靜默換線。
- **USB 斷線時無法保證立即 clear 裝置端狀態**：UI 明確顯示 interrupted，重連後強制 clear 且不自動 resume。
- **位置偽造可能違反第三方服務條款**：產品顯示風險，不承諾相容、不可偵測或帳號安全；本 change 不包含規避措施。
