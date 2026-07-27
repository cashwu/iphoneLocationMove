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
- 讓 tunnel process 從 launch 起就受到可取消 ownership管理，endpoint無回應或caller消失時不得遺留root process。
- 以公開`NSXPCConnection` security attributes建立connection-bound caller trust，並以production XPC acceptance驗證真實privileged boundary。

**Non-Goals**

- Wi-Fi、並行控制多裝置、隨機位置、背景常駐 menu bar product、內建 Python runtime 或公開發佈包裝。
- 防禦已取得root權限且可同時替換helper executable與root-owned runtime seal的攻擊者。
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

`iPhoneLocationMoveTunnelHelper/` 是透過 `SMJobBless` 安裝並向 launchd 註冊的 privileged helper，只提供 `startTunnel(deviceID, idempotencyKey)`, `stopTunnel(leaseID)`、`status(leaseID)` 與 `reconcile()`。Apple Development 簽署的本機開發版本使用此機制完成管理員核准；這不改變 typed XPC、caller trust、runtime integrity 或 cleanup contract。它不得接受 shell 字串、任意 flags、Python path、package path 或任意 output path。

privileged runtime payload 由 signed App bundle 內的 offline wheelhouse 提供。helper executable內嵌trust anchor固定external manifest、所有wheel digest、mode與固定offline build plan，MUST NOT從caller提供的manifest或path建立trust。helper只在root-owned、mode `0700`且不可由一般使用者修改的private staging中，以root-owned Python `>=3.9`執行固定的`pip install --isolated --no-index --no-compile --target`。build完成後helper遍歷canonical relative paths，拒絕symlink與non-regular file，為每個generated file記錄SHA-256、owner與mode，將排序後的完整集合寫成root-owned、mode `0600`的sealed runtime manifest，再驗證一次後atomic rename publish。每次start都必須驗證seal本身的owner／mode、完整file set無missing或extra、每個file無symlink且owner／mode／digest一致。此seal不防禦已取得root並可同時替換helper與seal的攻擊者，但一般使用者不能修改seal或runtime。root process MUST NOT執行network `pip`或user-writable interpreter／package／manifest／staging payload。

`NSXPCConnection`公開API不提供raw audit token。listener在`resume()`前讀取kernel提供的`processIdentifier`、`effectiveUserIdentifier`與`auditSessionIdentifier`，用PID取得dynamic `SecCode`並驗證固定designated requirement、Team ID與完整static code signature；驗證成功後建立只屬於該connection的`TunnelHelperXPCService`與不可重用`connectionID`。所有request只經該verified exported service抵達manager，並帶同一connection-bound identity；connection interruption／invalidation立即使identity失效並觸發owner cleanup。artifacts不再宣稱helper取得raw audit token。

#### Pending tunnel start ownership

helper以`TunnelStartKey(connectionID, deviceID, idempotencyKey)`識別active lease形成前的同一logical start。`TunnelLeaseManager`使用一個`NSCondition`保護`pendingStarts`與active leases；外部runtime build、process launch、endpoint read與process stop一律在condition lock外執行。

第一個start建立`PendingTunnelStart`後成為leader。process launch成功後，leader必須先把process附加到pending ownership，再讀endpoint；若invalidation已先把pending標成cancelled，leader立即停止process。endpoint read使用`poll(2)`或等價可中斷file-descriptor等待，deadline固定為15秒且line上限16 KiB。timeout、EOF、invalid endpoint、process exit或cancel都停止process、移除pending並broadcast terminal failure。

相同`TunnelStartKey`的concurrent或lost-reply retry不得launch第二個process；它在`NSCondition.wait(until:)`等待同一pending terminal result。成功時leader原子地把pending轉成唯一`TunnelLeaseID`並broadcast同一snapshot；失敗時所有waiter收到同一typed error。owner invalidation在condition內標記該owner全部pending為cancelled並取出已附加process，隨即release lock、停止process，再broadcast；因此不得等待leader持有的external I/O。

active lease仍以verified connection identity、device ID與idempotency key管理。同一caller／device的重複start回傳既有lease；start reply遺失可用相同key取得pending或active結果。XPC invalidation、owner death、App crash或explicit stop都回收pending start、active lease與root process。RSD endpoint透過受型別約束的XPC reply回傳；拒絕授權、handshake timeout、endpoint parse失敗、process提前退出或stop失敗都回傳結構化錯誤。

App每次`prepareSession`在selected device prerequisites完成、呼叫`startTunnel`之前，必須對新verified XPC connection執行一次`reconcile()`。reconcile failure映射成typed tunnel setup failure，阻止start／DVT／ready；成功後才可建立新的pending start。quit teardown仍執行reconcile作為最後cleanup。

#### Production privileged acceptance

DEBUG App可接受固定enum形式的`--privileged-helper-acceptance-case`，只驅動既有typed XPC methods與固定fixtures，MUST NOT接受任意command、argument list、interpreter、package、manifest或output path。acceptance runner以production signed App、實際SMJobBless helper與root process驗證positive start、pending duplicate、lost reply retry、endpoint timeout、connection invalidation／App termination cleanup、startup reconcile及runtime seal tamper；非法／被竄改caller則以修改後signature-invalid copy與ad-hoc re-signed Team-ID-mismatch copy驗證listener拒絕。每個case輸出固定schema到stdout，最終uninstall後確認service、fixed paths與相關root process均不存在。

這個 root-owned tunnel runtime 不等同公開發佈版的內建 Python runtime；它只服務必要的 privileged tunnel，公開發佈前仍須完成簽署、公證、第三方授權與更新策略評估。

### 7. Device session 與 reconnect

`PymobiledeviceAdapter` actor 序列化所有 mutating operation，並以遞增的 `DeviceSessionGeneration` 標記 connect/reconnect。來自舊 generation 的 helper 或 tunnel callback 一律忽略。

準備順序固定為 runtime probe → USB discovery／device selection → trust 與 Developer Mode 檢查 → DDI mount → tunnel → DVT helper ready。任何階段失敗都停在具體狀態並提供對應修復資訊，不得跳過 prerequisite。

tunnel階段的內部順序固定為建立verified XPC connection → `reconcile()` → `startTunnel`。`reconcile()` failure不得被忽略或降級成warning，也不得繼續建立新lease。

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
   - privileged helper SHALL以固定designated requirement／Team ID、caller code signature與helper executable內嵌input digest table驗證signed App bundle payload；generated runtime SHALL由root-owned private staging建立sealed digest manifest、atomic publish，並在每次start前驗證完整file set、owner、mode、symlink與digest。
   - 每個XPC request SHALL只經listener已驗證的connection-specific exported service抵達manager；identity SHALL綁定`processIdentifier`、`effectiveUserIdentifier`、`auditSessionIdentifier`與不可重用`connectionID`，不得宣稱使用公開API未提供的raw audit token。
   - `PendingTunnelStart` SHALL以`TunnelStartKey`與`NSCondition`管理launch至active lease之間的ownership；15秒endpoint deadline、owner invalidation、timeout與parse failure都 SHALL回收root process，同key重試 MUST NOT launch第二個process。
   - production adapter SHALL在每次start tunnel前成功執行`reconcile()`；failure MUST阻止DVT與ready。
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
   - privileged-helper deterministic tests SHALL驗證`PendingTunnelStart`的leader／waiter、invalidation-before-process-attach、hanging endpoint deadline、同key單一launch、startup reconcile ordering／failure、connection-bound identity、runtime seal的missing／extra／digest tamper與所有terminal cleanup。
   - privileged-helper production acceptance SHALL使用DEBUG fixed-case runner與實際SMJobBless helper驗證真實owner／mode／digest、invalid signature／Team ID caller rejection、pending／active idempotency、lost reply、endpoint timeout、XPC invalidation／App termination、startup reconcile、runtime seal tamper與uninstall cleanup；fake harness不得作為這些production cases的唯一證據。
   - physical-device acceptance SHALL 在一台 iOS 17+ USB iPhone 上驗證單點、單程、往返、pause、quit clear 與拔線／重連；自動化測試不得要求實體 iPhone。

## Risks / Trade-offs

- **Apple 或 `pymobiledevice3` protocol 改變**：capability probe 與 typed adapter 限制影響面；版本更新必須重新跑 physical-device acceptance。
- **Privileged helper 擴大攻擊面**：以固定 typed XPC contract、audit identity、lease ownership、offline hash-locked payload、symlink／mode／digest 驗證、atomic install、owner-death cleanup 與最小權限降低風險。公開發佈前必須另做 security、dependency licensing 與 signing review。
- **DEBUG acceptance runner 被誤用**：只接受編譯期固定case enum與typed XPC methods，不接受任意path／command／argument；Release build完全不編譯此入口。
- **Root attacker 可替換runtime seal**：本change的threat model只保證一般使用者與被竄改caller不能改寫privileged runtime；已取得root並能替換helper executable者不在此boundary內。
- **App-managed venv 安裝依賴網路與既有 Python**：提供可重試進度與明確離線／缺 Python 指引；不在第一版偷偷安裝 system dependency。
- **MapKit route 可能不存在或動態改變**：沒有 pedestrian route 時禁止開始並保留 A、B 供修改；active session 使用已確認的 immutable polyline，不在途中靜默換線。
- **USB 斷線時無法保證立即 clear 裝置端狀態**：UI 明確顯示 interrupted，重連後強制 clear 且不自動 resume。
- **位置偽造可能違反第三方服務條款**：產品顯示風險，不承諾相容、不可偵測或帳號安全；本 change 不包含規避措施。
