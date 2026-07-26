## 1. Project foundation

- [x] 1.1 建立 `iPhoneLocationMove.xcodeproj/`，加入 macOS 13+ App、`iPhoneLocationMoveTests/` unit test 與 `iPhoneLocationMoveTunnelHelper/` privileged helper targets，設定可重現的 schemes、entitlements 與 test command。
- [x] 1.2 在 `iPhoneLocationMove/` 建立最小 SwiftUI App shell 與 feature／domain／device 目錄；確認空殼可 build，且關閉視窗後可重新開啟主視窗。

## 2. Parallel test-first foundations

- [x] [P] 2.1 先在 `iPhoneLocationMoveTests/RouteSessionTests.swift` 撰寫 failing tests，逐項涵蓋 design §3 transition table、`900 m @ 4.5 km/h = 12 minutes`、monotonic timer delay、pause/resume、confirmed-distance speed rebase、單程完成、endpoint overflow、往返週期與 running-only sleep pause；再於 `iPhoneLocationMove/Domain/RouteSession.swift` 實作最小通過行為。（覆蓋 requirements：`步行速度與距離進度`、`暫停、繼續與即時調速`、`單程完成與往返循環`）
- [x] [P] 2.2 先在 `iPhoneLocationMoveHelper/tests/` 撰寫 failing protocol tests，並建立 tests 使用的 `iPhoneLocationMoveHelper/tests/fixtures/` 有效／錯誤 messages；再於 `iPhoneLocationMoveHelper/` 實作不執行 shell 的 newline-delimited JSON DVT helper與 `iPhoneLocationMoveHelper/PROTOCOL.md`，涵蓋 malformed JSON、未知 command、無效座標、request ID correlation、`set`／`clear` failure 與 graceful shutdown。
- [x] [P] 2.3 先在 `iPhoneLocationMoveTests/RuntimeManagerTests.swift` 撰寫 failing tests，涵蓋 capability probe、相容既有安裝、版本存在但缺 `--script-mode`、Python 缺失、安裝取消／失敗與 incomplete venv；再於 `iPhoneLocationMove/Device/RuntimeManager.swift` 實作 App-managed venv 流程與 pinned lock manifest。（覆蓋 requirement：`相容的裝置支援環境`）
- [x] [P] 2.4 先在 `iPhoneLocationMoveTests/TunnelHelperContractTests.swift` 撰寫 failing tests，涵蓋 caller audit identity、App code signature／designated requirement／Team ID、helper executable 內嵌 digest table、payload 與外部 manifest 同時替換、device ID、`TunnelLeaseID` ownership、idempotent start、非法 request、endpoint parse、process 提前退出、stop failure、XPC invalidation／owner death、symlink／owner／mode／digest tamper 與 atomic install；再於 `iPhoneLocationMoveTunnelHelper/` 實作只接受 typed `startTunnel(deviceID, idempotencyKey)`／`stopTunnel(leaseID)`／`status(leaseID)`／`reconcile()` 的 `SMAppService` XPC helper，以及從通過 App signature 與 helper trust anchor 驗證的 `iPhoneLocationMoveTunnelHelper/Resources/tunnel-wheelhouse/` 建立的 root-owned runtime。root process 不得執行網路 `pip` 或 user-writable interpreter／payload／manifest。（覆蓋 requirement：`最小 privileged tunnel 邊界`）

## 3. Device session adapter

- [x] 3.1 在 `iPhoneLocationMove/Device/DeviceLocationClient.swift` 定義 UI 所需的最小 typed contract、device／runtime／session states、typed errors、typed interruption reason／position knowledge payload、`SimulationSessionID` 與 `DeviceSessionGeneration`；`positionUnknown` 是 `interrupted` 的 payload 而非獨立 state，且 contract 不暴露 process、JSON 或 shell 細節。
- [x] 3.2 先在 `iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift` 撰寫 failing tests，涵蓋 prerequisite 固定順序、零／一／多 USB device、iOS 17 以下阻擋、單一 mutating command、request correlation、stale session suppression、generation replacement、active-device switch transaction／途中拔線、USB 中斷的 `interrupted(positionUnknown)` payload、authorization denial、transport failure、disconnect cleanup、reconnect-before-clear、ready-session quit teardown 與 clear failure。（覆蓋 requirements：`裝置 prerequisite 準備順序`、`序列化且可關聯的裝置命令`）
- [x] 3.3 在 `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift` 實作唯一 production adapter，整合 `RuntimeManager`、tunnel XPC 與 DVT helper；使 3.2 測試通過，並確認舊 generation／session callback 不會改寫 current state。

## 4. Map and simulation features

- [x] [P] 4.1 先在 `iPhoneLocationMoveTests/LocationMapModelTests.swift` 撰寫 failing tests，涵蓋搜尋結果 preview、out-of-order search、search in flight → map click → old response、清除搜尋後 stale response、地圖點擊 preview、A／B selection、A／B change during directions、no-route／cancel／transient failure／stale result、immutable polyline、endpoint snapshot、distance 與 ETA；再於 `iPhoneLocationMove/Features/Map/LocationMapView.swift` 及其 model 實作所有 preview ownership change 都遞增的 `MapSearchGeneration`、`RouteRequestGeneration` 與 MapKit UI，確保選點不直接 mutate device。（覆蓋 requirements：`地圖搜尋、選點與明確確認`、`A/B 步行路線預覽`）
- [x] [P] 4.2 先在 `iPhoneLocationMoveTests/SimulationStoreTests.swift` 撰寫 failing tests，涵蓋單點確認、route 從 A 開始、point／route replacement 及首次 mutation failure、約一秒 scheduling、single-in-flight latest-only coalescing、tick burst、pause-during-in-flight transaction、無 in-flight pause 不送額外 mutation、fake device 最終座標 correction、uncertain pause failure、pause/resume、調速時 in-flight success 後以 latest confirmed distance rebase、未確認 tick 不發布為 committed progress、調速結果不確定進入 `interrupted(positionUnknown)`、單程停留 B、往返、mid-route set timeout、helper／tunnel exit、stop clear、clear failure、stale `SimulationSessionID`／`RouteUpdateEpoch` 與 risk prompt cancellation；再於 `iPhoneLocationMove/Features/Simulation/SimulationStore.swift` 實作可觀察狀態與 command orchestration。（覆蓋 requirements：`單點定位模式`、`路線更新背壓與操作屏障`、`模擬模式互斥與安全取代`、`停止模擬與 clear 確認`）
- [x] 4.3 整合地圖與 simulation controls：提供單點「設定位置」、A／B route preview、`1–7 km/h` speed control、`往返循環`、開始、暫停、繼續及「停止模擬」，並讓所有 mutating actions 經明確確認與 `DeviceLocationClient`。

## 5. Lifecycle, interruption, and recovery

- [x] 5.1 先新增 App lifecycle tests，驗證關閉視窗不結束 active session、quit confirmation、producer → clear → DVT shutdown → tunnel stop 順序、強制退出警告，以及 clear failure 不得顯示已恢復真實定位；再實作 `iPhoneLocationMove/App/iPhoneLocationMoveApp.swift` 的 lifecycle coordination。（覆蓋 requirement：`App 結束時清理裝置 session`）
- [x] 5.2 先新增 disconnect／reconnect integration tests，驗證拔線後停止 tick、`interrupted(positionUnknown)` 呈現、同一裝置新 generation、reconnect 後先 clear、clear success 前保持非 ready，且不自動 resume；再完成 adapter 與 `SimulationStore` 的 recovery integration。（覆蓋 requirement：`USB 中斷與安全重連`）
- [x] 5.3 加入 macOS sleep／wake observation，並以 fake in-flight device request 驗證只有 running route 的 sleep 會觸發同一個 `pausing` transaction：睡前來不及完成時維持 `pausing`，wake 後 last confirmed coordinate 等於 snapshot 才 paused，不確定結果進入 `interrupted(positionUnknown)`，睡眠時間不會轉成位置距離，且 point active／route completed 收到 sleep notification 時不進入 `pausing`。（覆蓋 requirement：`系統睡眠與裝置中斷不造成位置跳躍`）

## 6. Setup and user-facing failure states

- [x] 6.1 實作 runtime 與 device setup UI：顯示 probe 結果、一鍵安裝進度／取消／重試、無 Python／privileged-safe Python 指引、privileged helper 授權與 prerequisite-specific 修復資訊；零裝置顯示 USB／信任提示，單台自動選擇並顯示名稱／iOS 版本，多台提供明確 selection，iOS 17 以下標記 unsupported，未選定或 unsupported 時禁止建立 session。不得修改 global Python 或 Homebrew。（覆蓋 requirement：`USB 裝置偵測與選擇`）
- [x] 6.2 實作首次使用與每次模擬前的第三方服務條款風險提醒；確認文案不承諾不可偵測、規避反作弊或帳號安全。
- [x] 6.3 為 timeout、USB disconnect、authorization denial、DDI failure、tunnel failure、helper failure 與 clear failure 提供可區分且可操作的 UI，並驗證任何失敗都不會誤報 ready／active／cleared。

## 7. Verification and documentation

- [x] [P] 7.1 執行 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS'`，修正所有 unit／integration test failure，並確認一般自動化測試不要求實體 iPhone 或 root。
- [x] [P] 7.2 執行 `python3 -m unittest discover -s iPhoneLocationMoveHelper/tests`，驗證 helper protocol 與錯誤路徑。
- [ ] 7.3 在隔離測試環境完成需管理員核准的 privileged-helper acceptance：驗證實際安裝路徑 owner／mode／digest、payload 與外部 manifest 同時替換、invalid App signature／designated requirement／Team ID、symlink／staging／manifest tamper fail closed、合法與非法 caller、idempotent start、遺失 start reply reconcile、XPC invalidation／App crash 回收、重複 start 不產生第二個 tunnel，以及 uninstall／cleanup；記錄結果且不得對開發機留下 root process。
- [ ] 7.4 在一台 iOS 17+ USB iPhone 完成 physical-device acceptance：runtime probe、單點、`900 m` 單程、往返、pause/resume、調速、stop clear、quit clear、ready-without-active quit、USB 拔除／重連及拒絕授權；記錄版本與結果。active-device switch transaction 由 task 3.2 的 fake-boundary integration test 驗證，不要求此單裝置 acceptance 模擬第二台裝置。
- [x] 7.5 建立 `README.md`，記錄 macOS／iOS prerequisite、Python fallback、Developer Mode、USB、授權、build／test、故障排除、清除定位方法、privileged helper uninstall、GPL-3.0／公開發佈待辦與第三方服務條款風險。
- [ ] 7.6 執行 change validation 與 scope review，確認只新增 proposal `## Impact` 宣告的 targets／directories，`openspec/specs/ios-device-session/spec.md` 與 `openspec/specs/location-simulation/spec.md` 的所有 scenarios 都有對應 task 或 acceptance verification，且未加入 Wi-Fi、多裝置並行、隨機位置、內建 Python runtime 或反偵測功能。
