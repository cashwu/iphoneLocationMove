# 已完成的 Change 歷史

依時間順序列出專案所有已完成並合併進 [`specs/`](specs/) 的 change：目標、關鍵設計決策、影響的 spec 與已完成的 tasks。目前沒有進行中的 change。

## 2026-07-27 add-macos-location-simulator

**目標**：建立原生 macOS App，讓使用者經 USB 控制一台 iOS 17+ iPhone 的模擬定位，提供單點定位與 A/B 步行路線（預設 4.5 km/h，可調 1–7 km/h、暫停／繼續、往返），取代手動在終端機建 tunnel 與輸入座標。同時補強 privileged helper 邊界：等待 RSD endpoint 的 tunnel process 即受 ownership 管理，並以 production XPC 驗收證明負向安全案例。

**關鍵設計決策**：
- SwiftUI + MapKit；`SimulationStore` 為 UI 單一 owner，裝置邊界只有一個 actor `PymobiledeviceAdapter`（內含 Python DVT helper、runtime manager、tunnel XPC），單點與路線兩模式互斥，以 `SimulationSessionID` 隔離過期的非同步結果。
- `RouteSession` 狀態機：進度由 monotonic 時間 × 速度算出距離（非固定步長累加）；每次最多一個 in-flight `set`、latest-only coalescing，pause／調速以 `RouteUpdateEpoch` barrier 與 correction `set` 確保座標不倒退；任何不確定結果進 `interrupted(positionUnknown)`，不自動 resume。
- Privileged tunnel helper 以 `SMJobBless` 安裝，只接受 typed XPC（`startTunnel`／`stopTunnel`／`status`／`reconcile`）；caller 在 `resume()` 前以 PID 驗 code signature／designated requirement／Team ID 並綁定唯一 `connectionID`（公開 API 無 raw audit token）。
- root runtime 只由 App bundle 內的 offline wheelhouse 以 `pip install --no-index --target` 建在 root-owned staging，產生 mode 0600 的 sealed digest manifest 後 atomic publish，每次 start 重驗完整檔案集合；不執行 network `pip` 或 user-writable payload。不防禦同時取得 root 並替換 helper 與 seal 的攻擊者。
- `PendingTunnelStart`（以 `TunnelStartKey` + 單一 `NSCondition`）管理 launch 到 active lease 之間的 ownership：endpoint 15 秒 deadline、同 key 重試不重複 launch、invalidation 於 attach 前後皆回收 process；App 每次 prepare 在 start tunnel 前必須先 `reconcile()`，失敗即阻止 ready。

**影響的 spec**：`ios-device-session`、`location-simulation`（皆為新增）

**已完成 tasks**：
- [x] 1.1 建立 Xcode project：macOS 13+ App、unit test 與 privileged helper targets
- [x] 1.2 建立 SwiftUI App shell 與目錄結構，關閉視窗後可重開
- [x] 2.1 RouteSession 狀態機與距離／速度／暫停／往返／sleep pause（含測試）
- [x] 2.2 Python DVT helper 與 newline-delimited JSON protocol（含測試與 PROTOCOL.md）
- [x] 2.3 RuntimeManager：capability probe 與 App-managed venv 安裝（含測試）
- [x] 2.4 privileged tunnel helper：typed XPC、caller 驗證、offline runtime 建置（含測試）
- [x] 3.1 定義 DeviceLocationClient typed contract 與 session／error 型別
- [x] 3.2 PymobiledeviceAdapter 測試：prerequisite 順序、裝置切換、斷線、reconnect
- [x] 3.3 實作唯一 production adapter，過期 generation／session callback 不改寫狀態
- [x] 4.1 地圖搜尋、選點、A/B 與步行路線預覽，含 stale response 防護
- [x] 4.2 SimulationStore：單點、路線、取代、coalescing、pause／調速／stop／clear
- [x] 4.3 整合地圖與模擬控制，所有 mutation 經明確確認
- [x] 5.1 App lifecycle：關窗不結束、quit 確認與 clear→shutdown→stop tunnel 順序
- [x] 5.2 USB 斷線／重連：reconnect 後先 clear 才 ready，不自動 resume
- [x] 5.3 sleep／wake：僅 running route 觸發 pausing transaction
- [x] 6.1 runtime 與裝置設定 UI：安裝進度、多裝置選擇、iOS 17 以下標示 unsupported
- [x] 6.2 首次使用與每次模擬前的第三方服務條款風險提醒
- [x] 6.3 各類失敗（timeout、斷線、授權拒絕、DDI、tunnel、helper、clear）可區分的 UI
- [x] 6.4 TunnelHelperContractTests：pending start 的 race、重試與 deadline 測試
- [x] 6.5 Adapter 測試：tunnel 階段固定 reconcile→start，reconcile 失敗 fail closed
- [x] 6.6 實作 PendingTunnelStart／TunnelStartKey／NSCondition 與 15 秒 poll deadline
- [x] 6.7 adapter 在每次 prepareSession 的 start tunnel 前呼叫 reconcileTunnels
- [x] 6.8 caller trust 綁定 PID／UID／audit session／connectionID，移除 raw audit-token 宣稱
- [x] 6.9 generated runtime sealed digest manifest 與每次 start 的完整驗證
- [x] 6.10 DEBUG 固定 enum 的 production XPC acceptance runner（Release 不編譯）
- [x] 6.11 production acceptance 步驟與 fixtures：負向 caller 副本、root tamper、uninstall 確認
- [x] 7.1 執行 xcodebuild 單元／整合測試，不需實體 iPhone 或 root
- [x] 7.2 執行 Python helper protocol 測試
- [x] 7.3 隔離環境執行 privileged helper production acceptance 並確認清理乾淨
- [x] 7.4 一台 iOS 17+ USB iPhone 的實機驗收
- [x] 7.5 建立 README（prerequisite、build／test、故障排除、清除定位、helper uninstall、風險）
- [x] 7.6 scope 檢查：spec scenarios 皆有對應 task／驗收，未加入範圍外功能

**實作備註／偏離**：兩處機制替換、contract 不變。(1) root 的 `/usr/bin/python3 -m venv --copies` 無法避免 symlink，改以固定 `pip install --isolated --no-index --target` 安裝 wheelhouse 並產生固定 entrypoint；(2) `SMAppService.daemon` 在 Apple Development 簽署的 App 上回傳 `.notFound`（需 notarized），改用仍支援 macOS 13+ 的 `SMJobBless` 安裝 helper。

**驗收結果**：privileged helper 以原始 signed Debug App、真實 `SMJobBless` helper 與 production XPC 驗證通過（含簽章無效／Team ID 不符 caller 被拒、pending／retry 冪等、endpoint timeout、invalidation 清理、runtime seal 各類 tamper、uninstall 後無殘留）；過程中發現 Python 寫 bytecode cache 會使 seal 失效，已固定 `PYTHONDONTWRITEBYTECODE=1` 並補回歸測試。實機（iPhone 14 Pro、iOS 26.5.2、USB）由日誌獨立確認 runtime probe、4.5 km/h 往返路線（526 次 set 全成功）、stop clear 與 quit teardown，其餘操作依使用者簽核視為通過，未宣稱由日誌驗證。

---

## 2026-07-27 add-mac-recenter-and-workspace-reset

**目標**：在地圖控制欄新增「到 Mac 位置」（只移動鏡頭，不改預覽點或 iPhone 定位）與「Reset」（確認後把地圖工作區還原到剛開 App 的狀態並停止進行中的模擬），免去手動平移與逐項清除的繁瑣。

**關鍵設計決策**：
- 置中用新的可消耗 camera intent（`MacRecenterGeneration`／`MacRecenterIntent`，經 `LocationMapCameraEffects.applyMacRecenter` 同 generation 只套用一次、走 programmatic 路徑）；同一次 update 內最後套用，使用者剛下的置中指令勝出；任何使用者地圖操作會清除未消耗的 recenter intent。
- Reset 以 advance 方式作廢 search／geocode／directions 的 generation（不歸零，維持 stale-guard），view 端同時取消 in-flight 要求。
- Reset 後鏡頭分兩支：已有 Mac 位置就發布新的 recenter intent；尚無則重設 `userHasMapContext` 讓初始置中重新武裝（以 MODIFIED requirement 明文授權為唯一重新武裝路徑）。
- Reset 是「停止模擬」的超集合：執行當下若 `SimulationStore` 持有清理責任就呼叫既有 `stop()`，不新增狀態機分支；clear 失敗沿用既有失敗顯示與重試入口，不宣稱已恢復真實定位；busy 狀態（starting、replacing、無失敗的 stopping）時 Reset disabled。
- `roundTrip` 與模擬錯誤訊息 `message` 上移到 `LocationMapView` 持有（sibling view 共同 state 由共同 shell 擁有）；確認對話框由獨立 state 驅動，警語依是否有清理責任分兩種，抽成純函式 `ResetConfirmationContent.make(hasCleanupOwnership:)` 便於測試。

**影響的 spec**：`mac-map-initial-location`、`location-simulation`（皆為修改）

**已完成 tasks**：
- [x] 1.1 Model：MacRecenterGeneration／Intent、requestMacRecenter()、canRecenterOnMac 與新錯誤
- [x] 1.2 Model：resetWorkspace() 清空工作區、作廢 generation、依 Mac 位置分支處理鏡頭
- [x] 2.1 CameraEffects.applyMacRecenter 與 Canvas／Coordinator 套用順序（recenter 最後勝出）
- [x] 2.2 控制欄新增「到 Mac 位置」按鈕
- [x] 2.3 上移 roundTrip／message，新增 Reset 按鈕、確認對話框與重置後 stop 流程
- [x] 3.1 測試 requestMacRecenter 的錯誤、identity 遞增與 intent 清除
- [x] 3.2 測試 resetWorkspace 清空狀態、舊回應判 stale、有／無 Mac 位置兩分支
- [x] 3.3 測試 applyMacRecenter gate 去重與 ResetConfirmationContent 兩種警語
- [x] 3.4 hosting-view 測試：Reset 確認流程、busy disabled、有無清理責任、clear 失敗保留重試
- [x] 3.5 以 xcodebuild 執行完整測試並全數通過

**實作備註／偏離**：SwiftUI controls 在測試環境無法直接由 accessibility tree 操作，改以既有 marker 模式加入 DEBUG-only 的零尺寸 action marker 驅動 UI action；初版 marker 直接呼叫 reset 而繞過確認，後修正為 Reset marker 只觸發確認呈現、確認 marker 僅在對話框顯示時才能執行 reset，並補上「確認前工作區不變」的斷言。

---

## 2026-07-27 add-package-app-script

**目標**：新增可從任意工作目錄呼叫的 `Scripts/package-app.sh`，統一執行測試、清理、Release 建置、簽署驗證與 DMG 包裝，避免漏跑測試，以及 ad-hoc 簽署破壞 App 與 `SMJobBless` helper 的同 Team trust。

**關鍵設計決策**：
- 腳本以 `BASH_SOURCE[0]` 解析 project root（支援含空白路徑、macOS Bash 3.2），使用固定的 `iPhoneLocationMove` scheme 與 `build/DerivedData`、`build/Export`；clean 前先驗證 project 與 shared scheme 存在。
- 預設先跑 Xcode tests 與 `python3 -m unittest discover -s iPhoneLocationMoveHelper/tests`，任一失敗即不進入 Release build；flags：`-h`／`--help`、`-v`／`--version`、`--no-clean`、`--skip-tests`、`--no-dmg`。
- 保留 Xcode 原簽署，不呼叫 `codesign --force`／ad-hoc re-sign；build 後驗證 App／helper 的 strict signature、固定 identifier 與 Team `2LRM76M575`，並從 built helper 的 `__TEXT,__info_plist` 擷取實際 plist，驗證 `SMPrivilegedExecutables`／`SMAuthorizedClients` 雙向 requirement（不以 source plist 代替）。
- `--version` 以 `MARKETING_VERSION` 只傳給該次 `xcodebuild`（`Info.plist` 改引用 `$(MARKETING_VERSION)`，project 預設 `1.0`），並驗證 built App 的 `CFBundleShortVersionString`、DMG 檔名帶版本；不修改 project file。
- DMG 以 `hdiutil create -format UDZO` 打包 `.app` 與 Applications symlink，staging 與驗證暫存檔皆由 trap 清除；`Scripts/tests/package-app-tests.sh` 以 PATH shims 在隔離 fixture 驗證 orchestration，不需真實簽章。

**影響的 spec**：`macos-build-packaging`（新增）

**已完成 tasks**：
- [x] 1.1 contract tests：fixture、PATH shims、help／version／未知選項／marker 缺失不清理
- [x] 1.2 contract tests：預設流程與各 flags、版本傳遞、輸出路徑、命令順序
- [x] 1.3 contract tests：各種失敗邊界、簽署／requirement mismatch 與暫存清理
- [x] 2.1 腳本骨架：路徑解析、marker 驗證、help 與參數／版本格式解析
- [x] 2.2 MARKETING_VERSION 接線，實作 clean、tests、Release build 與 App metadata 驗證
- [x] 2.3 helper metadata 擷取、簽署與雙向 requirement 驗證、DMG 打包與成功摘要
- [x] 2.4 腳本設為 executable，跑通 orchestration tests
- [x] 3.1 README 記錄 prerequisites、流程、flags、產物路徑與未公證限制
- [x] 3.2 執行既有 Xcode 與 Python 測試
- [x] 3.3 本機實跑 `--no-dmg` 與預設 DMG 流程，確認簽署與版本化 DMG 輸出

**實作備註／偏離**：universal 的 embedded helper 直接 `otool | xxd -r -p` 會解出無效 plist，改為先 `lipo -thin "$(uname -m)"` 取單一 architecture slice，再以 `awk` 去除 address 並正規化 word byte order 後交給 `xxd`；仍以 built helper 為 oracle。

---

## 2026-07-27 fix-map-sidebar-control-layout

**目標**：修正加入「到 Mac 位置」與「Reset」後側欄按鈕重疊、寬度與水平位置不一致，以及 DEBUG 測試 marker 干擾畫面的視覺 regression，不改任何按鈕行為。

**關鍵設計決策**：
- 新增 file-private `mapSidebarPrimaryActionLayout()`（`.frame(maxWidth: .infinity, alignment: .leading)`）套用到所有單列按鈕；同列按鈕維持 `HStack(spacing: 8)`、不用 `Spacer`；「到 Mac 位置」與 Reset 收進 spacing 8 的獨立群組。
- DEBUG 測試 marker 改用專用 `TestingActionButton: NSButton`（零 intrinsic size、不可接受或拒絕 first responder、透明、無 border／focus ring、非 accessibility element），使用點固定零尺寸且禁止 hit testing；Reset 仍須先經 production 確認。
- 以 DEBUG-only `TestingLayoutRegionView` 作為 layout probe，讓 hosting-view 測試讀取按鈕與狀態文字區域的實際 frame，驗證不越界、不重疊、同列間距 ≥ 8 pt、主要操作左邊界一致（容許 1 pt 誤差）。
- 同一個 connected hosting hierarchy 依序驅動 idle、busy、route running、route paused、stopping failure，每次重跑完整 oracle；原有 Reset 確認／disabled／clear failure 測試保留作為行為不變的 regression gate。

**影響的 spec**：`location-simulation`（修改）

**已完成 tasks**：
- [x] 1.1 套用共同單列布局、整理 top-level 操作群組與多按鈕 row 間距
- [x] 1.2 新增 `TestingActionButton` 並限制 marker 零尺寸、不可 focus
- [x] 1.3 新增 `TestingLayoutRegionView` layout probe 與狀態文字區域標記
- [x] 2.1 測試 helper：frame 轉換、marker／probe 收集，以及邊界、重疊、間距、baseline 斷言
- [x] 2.2 disconnected 初始畫面的布局與 marker 零尺寸測試
- [x] 2.3 connected 單一 hierarchy 依序驗證 idle、busy、running、paused、stopping failure
- [x] 2.4 保留並執行既有 Reset 確認、busy disabled、clear failure 測試
- [x] 3.1 執行 ContentViewTests 的 targeted 測試
- [x] 3.2 執行完整測試並檢視四種畫面無重疊、越界或 marker 外框

**實作備註／偏離**：SwiftUI 的 production `Button` 在 `NSHostingView` 中不會成為可遍歷的 `NSButton`，改由每顆按鈕背景的 DEBUG-only `TestingLayoutRegionView` probe 量測 frame；`TestingActionButton` 型別仍用於驗證 marker。

---

## 2026-07-27 fix-stale-simulation-controls

**目標**：修正同一視窗內裝置準備完成後，定位控制仍停在 disconnected／disabled 的問題；根因是 `LocationMapView` 持有初始 `nil` 的 `simulationStore` 快照，沒有觀察 nested 的 `DeviceSetupStore`。

**關鍵設計決策**：
- 新增薄的 `DeviceSetupContentView`，以 `@ObservedObject` 直接持有 `DeviceSetupStore`，組合 `DeviceSetupView` 與 `LocationMapView(simulationStore: store.simulationStore)`，`simulationStore` 建立時共同父層重算 body；`ContentView` 改為傳遞整個 setup store。
- 保留 `LocationMapView` 接收 optional `SimulationStore` 的小型 API，不讓 map feature 依賴整個 setup feature；`canStartRoute`、`SimulationControls` 與裝置 mutation 行為不變。
- 為 disconnected／connected controls root 加穩定 accessibility identifier（`simulation-controls-disconnected`／`simulation-controls-connected`）作為測試 seam，不依賴在地化文字或像素。
- 回歸測試用 `NSHostingView` + 測試用 `NSWindow`，在 `start()` 前建立 view、ready 後於同一 hosting view 驗證 controls 切換；新測試檔須同步登錄到 test target 的 Sources build phase。

**影響的 spec**：`location-simulation`（修改）

**已完成 tasks**：
- [x] 1.1 建立 ContentViewTests 回歸測試並登錄到 test target，確認修正前失敗
- [x] 2.1 新增 `DeviceSetupContentView` 觀察 setup store，`ContentView` 傳遞整個 store
- [x] 2.2 為 disconnected／connected controls 加 accessibility identifier
- [x] 2.3 重跑回歸測試並確認既有 DeviceSetupStore／LocationMapModel 測試通過
- [x] 3.1 執行完整 macOS 測試
- [x] 3.2 檢查 ContentView composition：未 ready 顯示 disconnected，ready 後顯示 SimulationControls

---

## 2026-07-27 recover-dropped-device-tunnel

**目標**：修正 iPhone 步行路線執行約一至數分鐘後，iOS 17+ RSD tunnel 路由消失（`[Errno 65] No route to host`、`ConnectionTerminatedError`）而永久中斷模擬的問題。做法是辨識可恢復的 tunnel／DVT transport failure，在同一台 USB iPhone 仍可用時重建 transport，並重播原本那筆絕對座標 mutation 一次。

**關鍵設計決策**：
- 將 logical `DeviceSessionGeneration` 與可替換的 `DeviceTransportGeneration` 分離，另用獨立的 `RecoveryOwnershipEpoch` 取消跨 `await` 的 recovery；recovery 成功不改變 logical session、不觸發 Mac 定位。
- `helper.py` 以 exception chain（`ConnectionTerminatedError` 與 socket／route errno）產生結構化 `transport-closed`，其餘為 `backend-failure`；Swift 不得以訊息字串判斷是否 recovery。
- tunnel helper 持續 drain stderr，保留 4 KiB tail 與 termination status，`status` 對已退出 process 回傳一次診斷 snapshot 後移除 lease；persistent `diagnostic.jsonl` 只寫 allowlisted 欄位（failure code、exception type、errno、lease state、termination status、stderr byte count），不寫 raw detail、RSD endpoint 或座標。
- recovery 為單次、non-recursive transaction，固定順序為停舊 DVT helper、probe lease、必須成功 stop 舊 tunnel、啟新 tunnel、在 candidate transport 重播、驗證 ownership 後才 atomic commit 並發布成功；status 為 exited 或 stop 失敗時 fail closed，不並存兩個 tunnel；每筆 mutation 最多兩次 device delivery。
- recovery 成功時 route 沿用同一 `SimulationSessionID` 與進度；`set` recovery 失敗進入 `interrupted(positionUnknown)`，`clear` recovery 失敗則保留 cleanup ownership 與 retry clear，不回 idle。

**影響的 spec**：`device-tunnel-recovery`（新增）、`location-simulation`（修改）

**已完成 tasks**：
- [x] 1.1 為 helper transport classifier 建立 failing tests（exception type、errno、causal chain、bounded detail）
- [x] 1.2 為 tunnel helper contract 建立 failing tests（stderr drain、4 KiB tail、status snapshot、lease 移除）
- [x] 1.3 為 adapter recovery 建立 failing tests（set／clear 單次 recovery、stale completion、ownership 失效時序）
- [x] 1.4 為 SimulationStore 建立 failing tests（單一 in-flight、成功保持 session、失敗語意）
- [x] 2.1 實作 `helper.py` pure transport classifier、2,048 字元 detail 上限，並同步 `PROTOCOL.md`
- [x] 2.2 實作 tunnel helper stderr drain、bounded tail、running／exited snapshot 與 exited lease 回收
- [x] 3.1 在 `DeviceLocationClient.swift` 定義 typed transport failure、transport generation、recovery epoch 與 candidate identity
- [x] 3.2 在 `PymobiledeviceAdapter` 實作單次 `set`／`clear` recovery transaction、ownership gate 與 allowlisted 診斷事件
- [x] 3.3 在 `SimulationStore` 同步 typed terminal failure 對應，不新增第二套 recovery state machine
- [x] 4.1 執行 helper Python 測試全數通過
- [x] 4.2 執行 macOS `xcodebuild test` 全部 Swift 測試通過
- [x] 4.3 驗證診斷 log 只含 allowlisted 欄位，且事件順序為 closed、started、status_probed、succeeded／failed
- [x] 4.4 實機長時間 route acceptance，並如實記錄執行與未執行項目

**實作備註／偏離**：第一次因環境沒有 USB iPhone 而暫停實機 acceptance；接上裝置後以 iPhone 14 Pro（iOS 26.5.2）補跑同一 route 5 分 7 秒、298 次 set 全數成功且無 failure／recovery 事件。實機強制 tunnel termination injection 未執行，單次 recovery 與完整診斷序列僅由 deterministic boundary tests 驗證。

---

## 2026-07-27 show-confirmed-iphone-route-marker

**目標**：步行路線模擬期間，在地圖顯示與 A／B 及 Mac 目前位置可區分的「iPhone 模擬位置」marker，並只依 iPhone 已成功確認的 route coordinate 更新，讓使用者直接看出模擬走到哪裡。

**關鍵設計決策**：
- marker 座標唯一來源是已確認的 route truth：`.route` 取 `RouteSimulationSnapshot.confirmedCoordinate`，`.stopping` 取同一 `RouteSession.confirmedCoordinate`；以 presentation-only 的 `SimulationStore.confirmedRouteMarkerCoordinate` 投影，不保存進度、不顯示預測或 pending 座標。
- 在 `LocationMapView.swift` 加入直接持有 `@ObservedObject SimulationStore` 的小型 wrapper 驅動 map canvas，不依賴 sibling `SimulationControls` 的重算。
- marker 生命週期：pending／recovery 中停在最後確認位置；pause、單程完成、position 仍可信的 stop／clear pending／clear failure 保留；clear 成功、session replacement、USB disconnect 或 position-unknown 中斷後移除，且之後進入 stopping 也不得重新顯示。
- Coordinator 的 annotation 改為依固定角色（preview、A、B、Mac、iPhone route）維護 registry，就地更新 coordinate，不再每次全量移除重建；route overlay 內容不變時保留同一個 `MKPolyline`。
- marker 更新只走 annotation 同步，不觸發 route fit、Mac initial center 等 camera effect，也不改變使用者手動 camera ownership；不做「跟隨 iPhone」。

**影響的 spec**：`location-simulation`（修改）

**已完成 tasks**：
- [x] 1.1 為 annotation／overlay identity 與 camera 零增量建立 failing tests（`LocationMapModelTests`）
- [x] 1.2 為同一 `NSHostingView` 內 marker 出現、移動、消失建立 failing rendered-hierarchy tests
- [x] 1.3 為 `confirmedRouteMarkerCoordinate` 各狀態投影建立 failing tests
- [x] 2.1 實作 `confirmedRouteMarkerCoordinate` 投影與 map observation wrapper
- [x] 2.2 將 Coordinator annotation 改為角色化 registry，並同步 route overlay identity
- [x] 3.1 執行 LocationMapModel／ContentView／SimulationStore 相關測試通過
- [x] 3.2 執行完整 macOS Swift 測試無回歸
- [x] 3.3 以 USB iPhone 實機目視驗收 marker 外觀、移動、pause、stop 移除與 camera 不重置

**實作備註／偏離**：實機驗收曾等待 tunnel helper 核准與外部 UI 控制工具故障，之後以 iPhone 14 Pro（iOS 26.5.2）人工完成。驗收中發現 A 與 iPhone 起點重疊時 marker 被 MapKit collision layout 抑制，已改用 `.required` display priority 與 `.none` collision mode 修正並重驗通過。

---

## 2026-07-27 show-mac-location-on-device-ready

**目標**：iPhone 完成 USB 準備後，用 macOS Core Location 取得 Mac 一次性目前位置，顯示「Mac 目前位置」marker，並在使用者尚未建立地圖脈絡時自動置中一次，改善初始地圖視角；不自動設定或變更 iPhone 模擬定位。

**關鍵設計決策**：
- 定位封裝成可注入的一次性 `MacLocationProviding`（只有 `requestCurrentLocation() async throws -> MapCoordinate`）；live 實作每次要求建新的 `CLLocationManager` context，以 manager identity 綁定 checked continuation，恰好 resume 一次，舊 manager 的 late callback 不得完成新要求。
- app-lifetime 的 `MacLocationCoordinator` 由 `AppDelegate` 持有，保存已要求的 `DeviceSessionGeneration` ledger 與快取結果，使視窗重建不重複要求；generation 換代時先取消並等待舊要求完成再啟動新的，晚到結果以 current generation 比對後丟棄。
- `LocationWorkspaceView` 直接以 `@ObservedObject` 觀察 `DeviceSetupStore`，避免 sibling subtree 不重算；Mac 定位資料流與 iPhone DVT 完全分離，成功或失敗都不呼叫 `setLocation`。
- Mac marker 與 camera effect 分離：marker 一律可更新，初始置中只在 model 與 canvas 都未觀察到使用者脈絡（搜尋、選點、A／B、路線、手動平移縮放）時發出一次；preview／route／Mac initial center 的 camera effect 都帶穩定 identity，只在 identity 改變時套用，annotation redraw 不重播。
- 定位失敗只顯示非阻塞訊息，不建立 marker、不套用 fallback 座標；`Info.plist` 僅宣告 `NSLocationUsageDescription`，只要求 When In Use，不做背景或持續定位。

**影響的 spec**：`mac-map-initial-location`（新增）

**已完成 tasks**：
- [x] 1.1 為 Core Location boundary 建立 failing tests（授權、錯誤、並行、取消、late callback、單次完成）
- [x] 1.2 為 Mac marker 獨立性、置中資格、使用者脈絡失效與 camera identity 建立 failing tests
- [x] 1.3 為 ready generation 只要求一次、stale 結果丟棄與不產生 `setLocation` 建立 failing tests
- [x] 2.1 實作 `MacLocationClient.swift`（protocol、typed error、live client、coordinator）
- [x] 2.2 在 `Info.plist` 新增 `NSLocationUsageDescription`
- [x] 2.3 以 xcodegen 同步 Xcode project 的新 source
- [x] 3.1 在 `LocationMapModel` 實作 Mac marker state、initial-center intent 與使用者脈絡失效規則
- [x] 3.2 新增 `LocationWorkspaceView` 觀察 `DeviceSetupStore` 並傳遞 ready generation
- [x] 3.3 讓 `AppDelegate` 持有唯一 `MacLocationCoordinator` 並注入各 `ContentView`
- [x] 3.4 `LocationMapView` 顯示 Mac marker 與失敗訊息，camera effect 依 identity 至多套用一次並回報手動互動
- [x] 3.5 相關三組測試全數通過，stale 案例使用可控 fake 而非 wall-clock delay
- [x] 4.1 執行完整 macOS `xcodebuild test` 並修正失敗
- [x] 4.2 在可授權定位的 Mac 上做 acceptance（授權、置中一次、晚到結果、拒絕時功能仍可用）
- [x] 4.3 以 spy 驗證 Mac 定位成功或失敗都不產生 `setLocation`，marker 文案固定為「Mac 目前位置」

**實作備註／偏離**：正式 bundle 已有 Core Location 授權且此 macOS 無法重設，臨時 bundle identity 也未跳出全新 prompt，因此首次授權 prompt 的 acceptance 改為混合方式：正式 signed app 驗證 USB ready、真實座標 marker、初始置中與控制可用，`notDetermined` prompt、允許、拒絕、服務停用、晚到結果、手動 camera 等由可控 production boundary tests 驗證。

---

## 2026-07-30 preserve-map-camera-on-click

**目標**：修正使用者放大或平移地圖後直接點擊選點，preview camera 被固定 1,500 公尺 region 覆寫、地圖縮回既定比例的問題；直接選點只更新 preview，保留點擊當下的完整視野。同時把 preview camera 去重依據由 coordinate 改為 `MapSearchGeneration`，並讓 camera precedence 依本輪是否實際套用 route fit 判斷。

**關鍵設計決策**：
- 在 `LocationMapModel` 分離 marker render state（`preview`）與 camera intent：新增帶 `MapSearchGeneration` identity 的 `MapPreviewCameraIntent`，搜尋選取成功時建立，直接點擊、`beginSearch`、`clearSearch`、Reset 時清除，reverse geocode 與 validation failure 不改變。
- Coordinator 永遠依 `preview` 同步 annotation，但只有 intent 非 `nil` 才呼叫 `applyPreview`／`centerMap(on:)`；直接點擊、其後的 reverse-geocode 地址 redraw，以及被判 stale 而忽略的舊 response 都不得有任何 camera operation。
- `applyPreview` 改以 `MapSearchGeneration` 去重，因此「搜尋 A、點擊 B、再搜尋 A」第二次仍會置中；新增 `consumePreview(_:)` 只記為已消耗、不動 camera。
- `applyRoute` 回傳本次是否實際套用新 route identity；新 route fit 優先並消耗同輪 preview identity，已消耗的 route identity 不再因 overlay 仍存在而遮蔽後續搜尋置中；Mac initial center 的 gate 維持 `preview == nil` 且位於同一 else-if chain 之後。
- 不採「先 setRegion 再還原」，避免兩次 camera mutation 與額外 delegate callback 造成手動／程式化互動誤判；camera 狀態不跨 App 重啟或 map canvas 重建持久化。

**影響的 spec**：`location-simulation`（修改）

**已完成 tasks**：
- [x] 1.1 為 model 的 preview camera intent 轉換建立 failing tests
- [x] 1.2 擴充 `CameraOperationSpyMapView` 分別計數三種 camera operation，建立直接點擊 camera 隔離的 failing tests
- [x] 1.3 為 identity 去重與 route／搜尋 precedence 建立 failing tests
- [x] 2.1 在 `LocationMapModel` 定義 `MapPreviewCameraIntent` 與 read-only `previewCameraIntent` 並維護各 transition
- [x] 2.2 在 `LocationMapView` 將 intent 傳入 canvas，僅 intent 非 `nil` 時置中
- [x] 2.3 `applyPreview` 改以 generation 去重，新增 `consumePreview(_:)`，`applyRoute` 回傳是否套用並調整 precedence
- [x] 3.1 執行 `LocationMapModelTests` 通過
- [x] 3.2 執行完整 macOS 測試套件無回歸

**實作備註／偏離**：完整測試在 macOS 26.6 關閉 SwiftUI reset confirmation sheet 時，於 AppKit `NSSheetMoveHelper` 發生 `EXC_BAD_ACCESS`（與地圖程式碼無關）。先以 `NSAutomaticWindowAnimationsEnabled=NO` 執行；因同一 test host 連續開關不同 sheet 仍會 crash，最後把完整 suite 等價拆成多個獨立 `xcodebuild test` 程序（非 sheet 測試、`ContentViewTests`、各 reset sheet 測試各自執行），所有測試與斷言仍執行。

---

## 2026-07-31 fix-repeat-search-result-selection

**目標**：修正搜尋結果清單在第一次選取後仍顯示、但後續點擊不再生效的缺陷。只要結果仍可見，每次選取任一結果（含再次選取同一個）都更新 preview marker，並以新的 camera intent 將地圖移到該結果。

**關鍵設計決策**：
- 將 MapKit response ownership（`MapSearchRequest`，只負責拒絕 stale response）與結果列選取有效性分開：選取邊界改為目前 `searchResults` membership，model 入口收斂為 `selectSearchResult(_:)`，不在集合內則丟 `staleSearchSelection` 且狀態不變。
- 每次成功選取都呼叫既有 `advanceSearchOwnership()` 遞增 `MapSearchGeneration`、更新 `preview`、建立新的 `MapPreviewCameraIntent`，不以座標相等去重，因此重複選同一列也會重新置中；成功後清除 `activeSearchRequest` 但保留 `searchResults`，直到新搜尋、直接選點、清除搜尋或 Reset。
- View 的結果列 action 不再以 view-local `searchRequest` 做 guard，固定先呼叫 model，成功後才取消 view-local 搜尋／reverse-geocode 並清除 `searchRequest`；重繪前殘留的舊列 action 被 model 拒絕時只顯示錯誤，不得取消較新的 async 操作。
- 不新增 identity type、state machine 或 module；route precedence 與 preview 單次消耗機制不變。
- 測試 seam：在同一 `NSHostingView<LocationMapView>` 以 DEBUG-only 的每列 `TestingActionMarker`（零尺寸、不可 hit-test、非 accessibility element）觸發與可見列相同的 action；並以 DEBUG-only 的 `onSearchCancellationRequested`／`onPreviewAddressCancellationRequested` observers 觀察取消路徑是否被要求，Release build 不含這些 closure。

**影響的 spec**：`location-simulation`（修改）

**已完成 tasks**：
- [x] 1.1 為 model 建立 failing tests（連選 A、B、重複選同一列、非目前結果丟 stale selection）
- [x] 1.2 建立同一 rendered hierarchy 的 failing tests（連續選取、手動移開 camera 後再選、殘留舊 action 不取消較新操作）
- [x] 2.1 將 model 選取入口改為 `selectSearchResult(_:)`，以 `searchResults` membership 驗證並每次建立新 intent
- [x] 2.2 更新既有 `LocationMapModelTests` 對新 API 的呼叫與斷言
- [x] 2.3 移除 view 對 `searchRequest` 的 guard，改為先 model 後取消的順序，必要時加入 DEBUG-only action marker
- [x] 3.1 執行 `LocationMapModelTests` 與 `ContentViewTests` 通過
- [x] 3.2 執行完整 macOS 測試確認無回歸
- [x] 3.3 檢查最終 diff 範圍，確認未新增 identity type、state machine、module 或依賴
- [x] 4.1 將 cancellation observers 重新命名並限制在 `#if DEBUG`，Release build 不含
- [x] 4.2 在 stale rendered action 測試註明不等待 SwiftUI 重繪，並斷言錯誤訊息區域出現
- [x] 4.3 校對主 spec 既有 7 個 scenario 全數保留，新增 3 個 scenario
- [x] 4.4 執行 `ContentViewTests`、完整測試與 Release configuration build

**實作備註／偏離**：因 test target 一併編譯全部測試，view 層 red 驗證延後到 model API 可編譯後才執行；新增 cancellation observer 作為驗證 view-local 取消副作用的測試機制，之後收斂為 DEBUG-only。由於 Swift parser 不接受以 `#if DEBUG` 切開既有 initializer 參數列，改保留不含 observers 的 production initializer，另加 DEBUG-only overload 委派至它。

---

## 2026-08-27 add-favorites

**目標**：在 Mac 端地圖側欄加入「我的最愛」，讓使用者把已確認的預覽點位收藏起來，之後一鍵回到該點位再設為 A／B 或設定位置，省去重複搜尋或點選。收藏可取消、可改名，並以 `UserDefaults` 跨啟動保留。

**關鍵設計決策**：
- `FavoritesStore`（`@MainActor ObservableObject`，注入 `UserDefaults`）為唯一收藏 owner，由 `AppDelegate` 持有單一實例，避免多視窗（⌘0）各持一份造成 last-writer-wins 覆寫。
- 以 Codable DTO 陣列存單一 key；載入逐元素 lossy decode 並以 `MapCoordinate` 驗證座標，單筆壞資料只跳過該筆，整份非合法結構才歸零為空清單。DTO 無版本欄位屬刻意取捨。
- 「已收藏」以座標 Double 完全相等判定，toggle 已存在則移除、否則 append；預設名稱為地址快照，無地址時用 5 位小數座標文字。不引入 epsilon。
- 選用最愛走既有 generation 機制：`LocationMapModel.selectFavorite(_:)` 推進 `mapSearchGeneration`、設定 `preview` 與以新 generation 為 identity 的 camera intent（重複選同一筆也會重新置中），並清空搜尋結果與 in-flight 搜尋；不新增平行選點路徑。
- 最愛與 `LocationMapModel` 互不影響：刪除收藏不動 preview／A／B／模擬目標，工作區重置不清空最愛；view 端先過 `selectFavorite` 再取消 view-local 非同步 task。
- 重新命名為行內 `TextField`，submit 為唯一提交路徑，trim 後為空則保留原名，Esc／失焦丟棄。

**影響的 spec**：`favorite-places`（新增）

**已完成 tasks**：
- [x] 1.1 新增 `FavoritesStoreTests`：toggle、去重、預設名稱、remove／rename、順序、lossy decode、寫入失敗仍保持記憶體狀態
- [x] 1.2 在 `LocationMapModelTests` 新增 `selectFavorite` 測試（preview、camera identity、搜尋失效、identityExhausted）
- [x] 1.3 在 `ContentViewTests` 新增收藏 toggle、選用、rename、刪除不影響模擬、重置後保留的 view 測試
- [x] 2.1 新增 `FavoritesStore.swift`（`FavoritePlace`、載入／寫回邏輯）並以 xcodegen 重新產生 pbxproj
- [x] 2.2 在 `LocationMapModel` 新增 `selectFavorite(_:)`
- [x] 2.3 加入收藏 UI 與注入鏈：`AppDelegate` 單一實例、preview toggle 按鈕、最愛清單、右鍵重新命名／刪除
- [x] 3.1 執行完整測試確認既有行為無回歸
- [x] 3.2 檢查最終 diff 範圍，pbxproj 僅含新檔 registration，`project.yml` 無 diff

**實作備註／偏離**：首次跑 Red 階段時 Xcode 因 sandbox 無法寫入 DerivedData 失敗，解除限制重跑時實作已完成，因此 1.1、1.2 沒有取得有效的 Red 失敗紀錄。

---

## 2026-08-29 fix-device-locked-and-favorites-layout

**目標**：修正兩個獨立缺陷。其一，iPhone 螢幕鎖定時裝置準備失敗，畫面顯示整包 Python traceback 並被誤導為 DDI 問題；其二，「我的最愛」會把 iPhone 定位控制擠出可視範圍，且 layout 測試會讀寫執行者真實的偏好設定。

**關鍵設計決策**：
- 失敗摘要以 traceback 最後一條收框線為界，取其後行以單一空白接回 rich 折行；無方框時取最後一個有意義的行，全是雜訊時退回帶離開碼的固定訊息，上限 400 字元。雜訊以結構特徵判定而非固定字串清單。
- stderr 與 stdout 各自獨立摘要，顯示只取單一串流；分類對兩串流分別判定，鎖定優先於授權、授權優先於 prerequisite 失敗，且分類在截斷前進行。
- 「裝置螢幕鎖定」是裝置層級的 typed 失敗 `deviceLocked`（復原動作 `unlockDevice`），不併入授權被拒，因為修復動作不同；此優先序以刻意構造的輸入釘住。tunnel 與 DVT helper 階段不走 CLI，不在範圍內。
- 把「我的最愛」移到 iPhone 定位控制之後並加高度上限：實測最小視窗 900x620 下零筆最愛餘裕僅 22.5 點，只加高度上限無法解決，兩者缺一不可。收藏超過 5 筆才包入固定高度 104 的 ScrollView，避免貪婪的 ScrollView 在筆數少時留白。
- 移除 `FavoritesStore.init` 的 `UserDefaults` 預設值，讓呼叫端必須明示來源，由型別系統防止測試誤寫真實偏好設定。
- 已知取捨：摘要仍可能含裝置識別碼或家目錄路徑並寫入診斷紀錄，但寫入量比舊行為少；`deviceLocked`／`authorizationDenied` 不帶 message，誤判時無從由紀錄追查。

**影響的 spec**：`ios-device-session`、`favorite-places`（皆為修改）

**已完成 tasks**：
- [x] 1.1 為 `PymobiledeviceFailureSummary` 寫失敗測試：traceback 摘要、折行接合、無 traceback、串流隔離、截斷
- [x] 1.2 實作 `PymobiledeviceFailureSummary`：以收框線抽取摘要、過濾雜訊、400 字元上限
- [x] 1.3 為裝置鎖定分類寫失敗測試，並確認 pairing 訊息仍判為授權失敗
- [x] 1.4 新增 `deviceLocked` 失敗、`unlockDevice` 復原動作與呈現，標題與既有項目可區分
- [x] 1.5 抽出 `classify`／`failureIfReported` pure functions，依鎖定、授權、prerequisite 順序分類，exit 0 時仍辨識明確鎖定標記
- [x] 2.1 側欄 view 測試改用一次性隔離的 `UserDefaults` suite
- [x] 2.2 移除 `FavoritesStore` initializer 的 `UserDefaults` 預設值，App 兩處建構點明示 standard domain
- [x] 2.3 新增側欄版面回歸測試：設定位置按鈕位置不受收藏數影響、清單高度封頂、捲動可達最後一筆
- [x] 2.4 把最愛區塊移到 iPhone 定位控制之後，超過 5 筆時改為固定高度可捲動
- [x] 3.1 執行完整 macOS 測試套件與 Python protocol 測試，無回歸
- [x] 3.2 以實體 iPhone 手動確認 DDI 與 trust 階段鎖定時都顯示解鎖指引

**實作備註／偏離**：實機發現 `lockdown info` 在未信任且鎖定時會把 `Device is password protected. Please unlock and retry` 寫到 stderr 卻回傳 exit 0，因此改為在 exit 0 時仍對明確鎖定標記（及 trust 階段的明確授權標記）做同一分類。
**驗收結果**：iPhone 17 Pro（iOS 26.6.1）實機驗證通過：DDI 階段實際摘要為 `{'Error': 'DeviceLocked'}`，trust 階段為上述 exit 0 訊息，兩者都顯示解鎖指引、無 traceback，解鎖後重試可完成準備；測試後 pairing 與 DDI 已恢復。

---

## 2026-09-05 auto-reconnect-after-usb-replug

**目標**：修正「連接 iPhone 後拔除再插回，按下模擬就失敗且停止模擬也卡死」的問題。App 正式路徑沒有 USB 拔除偵測，tunnel 已 `exited` 時 recovery 回傳 generic `tunnelFailure` 並留下 stale session；現在把 `exited` 視為 USB 中斷，並在 start／stop 遇到中斷時自動 reconnect 一次後重發同一動作，使用者按一次即可成功。

**關鍵設計決策**：
- adapter 抽出 `markUSBDisconnected(oldSession:source:)`，tunnel status `exited` 時走與 USB 拔除相同的 teardown（進 `interrupted(positionUnknown)`、保留 disconnected device 記錄）並拋 `usbDisconnected`，不對該 lease 呼叫 `stopTunnel`；後續 set／clear 回傳 `usbDisconnected` 而非 `staleGeneration`。`usb.disconnected` 增加 `source`（`external`／`tunnel_exited`）。
- `reconnect()` 內 clear 失敗時（非 `usbDisconnected`）先同步清除 session 並設為 `cleanupPending`、再拆除剛建立的 tunnel／DVT，保證不留第二個 lease，下次仍可再 reconnect。
- `reconnect()` 納入 `DeviceLocationClient` protocol 且不提供預設實作；`SimulationStore.generation` 改為 `private(set) var`，僅在 reconnect 成功時更新。這是唯一的 identity 變更，`DeviceSetupStore` 與 Mac 位置要求不受影響。
- `SimulationStore` 新增 `reconnecting(mode:sessionID:)`：start 的第一筆 set 拋 `usbDisconnected` 時 reconnect 一次再以新 generation 重發；stop 的 clear 遇到時 reconnect 成功即等同 clear 成功。reconnect 回報 `noUSBDevice`／`deviceNotFound` 時視同 `usbDisconnected`。每次動作最多 reconnect 一次。
- 以 `userActionTask` 取代 `commandInProgress` 做 single-flight，`stopForQuit()` 會等待進行中的 reconnect；路線執行中 producer 遇到中斷維持 `interrupted`，不自動 reconnect 或 resume 舊路線。
- 不新增常駐 USB 監聽，閒置時拔線延後到下次使用者動作才發現（使用者已接受）；新增 `simulation.reconnect_started`／`succeeded`／`failed` 診斷事件，failure 只記 case 名稱。

**影響的 spec**：`device-tunnel-recovery`、`ios-device-session`、`location-simulation`（皆為修改）

**已完成 tasks**：
- [x] 1.1 為 adapter 的 tunnel `exited` 分類與 `reconnect` 收斂（含 clear 失敗拆除）加入失敗測試
- [x] 1.2 實作 `markUSBDisconnected`、`recoverTransport` 的 `exited` 分支，以及 `reconnect()` clear 失敗的收斂
- [x] 2.1 `DeviceLocationClient` 新增 `reconnect()`，六個測試 fake 補上該方法與所需測試 seam
- [x] 2.2 為 `SimulationStore` 自動重備加入失敗測試（start／stop 路徑、失敗分流、single-flight、退出等待）
- [x] 2.3 為側欄 `reconnecting` 呈現加入 view 測試（進度、控制項 disabled、成功與失敗後的畫面）
- [x] 2.4 實作 `SimulationStore` 自動重備、`reconnecting` 狀態、`userActionTask` single-flight 與 busy 枚舉，並更新 `LocationMapView`
- [x] 3.1 執行完整 macOS 測試套件，確認無回歸且不需改 `project.yml`
- [x] 3.2 以實體 iPhone 手動確認拔插後按一次即成功，並檢查 diagnostic log

**實作備註／偏離**：SwiftUI 在 `NSHostingView` 內不建立可讀取的文字／按鈕 view，因此 view 測試改以 layout region 識別碼與 `workspace-reset-button` disabled 驗證 `reconnecting` 畫面。本機憑證已撤銷，測試需加 `CODE_SIGNING_ALLOWED=NO` 等旗標，實機 build 需 `-allowProvisioningUpdates`。實機驗收未執行「路線中拔除後停止模擬」這條，改由自動測試涵蓋。另記錄既有 flaky 測試 `testDisconnectAfterStatusProbeCancelsRecoveryBeforeRestart` 與 `testQuitDuringCandidateTunnelStartCleansCandidateWithoutPublishingSuccess`（以單一 `Task.yield()` 當同步屏障），建議日後改用明確 boundary 屏障。

---

## 2026-09-17 fix-ios-27-usb-tunnel

**目標**：修正 macOS 27 搭配 iOS 27 時，舊版 `pymobiledevice3==9.36.3` 的 classic `lockdown start-tunnel` 在回傳 RSD endpoint 前退出、裝置無法 ready 的問題。升級到 `pymobiledevice3==11.13.0`，並讓 macOS 27+ 改走 `remote start-tunnel --native --script-mode`。

**關鍵設計決策**：
- 固定 pin `pymobiledevice3==11.13.0`（非追 latest），lockfile 為唯一來源；helper 內以 `TunnelRuntimePin` 集中保存 requirement 與版本化目錄名，generator 從 lockfile 導出 manifest 與 `GeneratedTunnelTrustAnchor.swift`，缺漏或不一致時 fail closed。
- capability probe 依 host policy 判定而非版本字串：macOS 27+ 要求 `remote start-tunnel` 含 `--native` 與 `--script-mode`，macOS 13–26 維持 `lockdown start-tunnel --script-mode`；兩者都要求 DVT `--rsd`。決策在啟動前做出，process 失敗後不 fallback。
- macOS 27+ helper 固定執行 `remote start-tunnel --native --script-mode --udid <id>`，並以 verified caller 的 effective UID 設定 `PYMOBILEDEVICE3_NATIVE_TARGET_UID`，讓 root helper 連到正確使用者的 `remotepairingd`；較早 macOS 維持 classic。
- root runtime 改裝到版本化目錄 `.../TunnelRuntime/pymobiledevice3-11.13.0`，不覆寫舊 `current`、不刪除舊版，以免把「舊版合法內容」與「同版本遭竄改」混為同一修復分支；seal／owner／mode／digest 驗證完整保留。
- 完成標準為 signed App 實機正向操作加完整自動測試；`run-production-acceptance.sh` 的完整 negative／cleanup suite 保留為額外 hardening，不阻擋封存，未執行時不得宣稱通過。

**影響的 spec**：`ios-device-session`（修改）

**已完成 tasks**：
- [x] 1.1 更新 user runtime pin 與 capability probe 為 host policy（macOS 27+ native、13–26 classic）
- [x] 1.2 重建 offline wheelhouse，generator 改從唯一 lockfile requirement 產生 manifest 與 trust anchor
- [x] 1.3 helper launcher 依 host policy 啟動固定 command，使用版本化 runtime 目錄，native 分支帶 verified caller UID
- [x] 1.4 production acceptance 新增走實際 preparation path 的 `device-session-ready` case，文件與 runner 對齊版本化 runtime
- [x] 1.5 保存 macOS 27 + iOS 27 實機正向操作與自動回歸結果

**驗收結果**：macOS 27 / iOS 27 實機以 Apple Development 簽署的 App 可連線、操作並成功定位；完整 macOS 測試 272 tests 0 failures，generator 8 tests OK，offline 安裝 `pymobiledevice3==11.13.0` 成功。完整 negative／cleanup suite 未執行，未宣稱其個別 case 通過。

---

## 2026-10-27 fix-ios-27-2-classic-tunnel

**目標**：修正 macOS 27.2 搭配 iOS 27.2 時 App 顯示「USB tunnel 失敗：The tunnel process exited before becoming ready.」的問題。移除前一個 change 加入的 macOS 27+ native tunnel 分支，讓所有受支援 macOS 都固定執行 `lockdown start-tunnel --script-mode --udid <deviceID>`，pinned `pymobiledevice3==11.13.0` 與 sealed runtime 不變。

**關鍵設計決策**：
- 實測依據：native tunnel 在 iOS 27.2 上 RSD handshake 成功但所有 service port 都 `ConnectionRefusedError(61)`（上游 #1994，iOS 27.2 在 native tunnel 只保留單一 RSD 連線，與 host `remoted` 互相驅逐），11.45.0 的 `--native` 同樣失敗。
- 上游 classic `remote start-tunnel` 在 helper 使用的 `/usr/bin/python3`（3.9.6、LibreSSL 2.8.3）上不可行：QUIC 被 iOS 拒絕，TCP 因 LibreSSL 無法選擇 PSK cipher 而失敗，因此不升級 pin 也不換 interpreter。
- 刪除 `TunnelHostPolicy`，launcher 固定 arguments 與固定 environment（不含 `PYMOBILEDEVICE3_NATIVE_TARGET_UID`）；`TunnelProcessLaunching.launch` 移除 `targetUserID`，caller trust 與 lease ownership 仍以 `VerifiedCaller` 為準。
- `RuntimeManager.hasRequiredCapabilities` 所有 host 使用同一組 probe，移除 `hostOperatingSystemVersion` 欄位。
- 不新增依 iOS 版本切換的 transport policy；已安裝的 `pymobiledevice3-11.13.0` root runtime 直接沿用。
- 已知風險：iOS 27.0–27.1 與 macOS 27 搭配 iOS 17.0–26.x 改走 lockdown 路徑未經實測，失敗時仍 fail closed 顯示 tunnel failure；若 Apple 移除 usbmux 上的 `CoreDeviceProxy`，此路徑會失效。

**影響的 spec**：`ios-device-session`（修改）

**已完成 tasks**：
- [x] 1.1 統一 capability probe 為 `lockdown start-tunnel --help` 含 `--script-mode`，移除 `hostOperatingSystemVersion`
- [x] 1.2 移除 `TunnelHostPolicy` 與 `targetUserID`，launcher 固定執行 classic command，同步更新 acceptance 手冊 process pattern
- [x] 1.3 以 signed App 在 macOS 27.2 + iOS 27.2 實機確認連線、定位與 3 分鐘路線模擬

**實作備註／偏離**：移除 host-version 輸入後，`testMacOS13Through26KeepsClassicTunnelCapability` 與預設 probe 測試完全重複，因此直接刪除該測試及其專用 stub，而非改寫。
**驗收結果**：signed App 1.0.8 實機通過：不再顯示 tunnel 失敗並進入 ready，定位成功，路線模擬連續至少 3 分鐘無中斷；完整 macOS 測試 271 tests 0 failures。`run-production-acceptance.sh` 的完整 negative／cleanup suite 未執行。
