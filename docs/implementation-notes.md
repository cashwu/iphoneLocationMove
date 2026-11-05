# 實作備註

實作過程中記錄的偏離（deviation）、阻塞與待決問題，依 change 時間排列。沒有條目的 change 代表實作過程無偏離。

### 2026-07-27 add-mac-recenter-and-workspace-reset

#### 2026-07-27 18:54 — Hosting 測試改用既有 marker 邊界
- 類別：deviation
- 任務：3.4
- 內容：原本嘗試由 `NSHostingView` 的 accessibility tree 直接取得並操作 SwiftUI controls，但目前測試環境只公開 repo 既有 `AccessibilityIdentifierMarker` 所建立的 `NSView` 邊界；改以同一既有模式加入零尺寸 action marker，讓 hosting tests 觸發相同的 SwiftUI state 與 action closure。
- 原因：此替代手段只改變測試驅動 UI action 的機制，不改變可觀察行為、interface／資料形狀、失敗模式或驗收標準，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

#### 2026-07-27 19:08 — 修正 hosting marker 的確認邊界
- 類別：deviation
- 任務：3.4
- 內容：Round 1 review 證實原 action marker 直接呼叫 `performReset`，實際上繞過確認 contract；現已改為 DEBUG-only、從 accessibility tree 隱藏的 testing marker，Reset marker 只呼叫 `presentResetConfirmation`，confirmation marker 僅在 `isResetConfirmationPresented == true` 時才可執行確認後的 reset，並新增確認前工作區不變的 hosting assertion。
- 原因：保留既有 marker 測試機制，但修正先前 deviation 對 contract 不變的錯誤判斷，使所有 production Reset 入口與 hosting verification 都維持「先確認、後重置」的相同行為邊界。

### 2026-07-27 add-macos-location-simulator

#### 2026-07-26 21:17 — privileged runtime 改用離線 target 安裝
- 類別：deviation
- 任務：2.4
- 內容：原設計預期以 root-owned Python 建立不含 symlink 的 managed runtime；實際的 `/usr/bin/python3 -m venv --copies` 回報 `This build of python cannot create venvs without using symlinks`。實作改為由同一個 root-owned、不可由一般使用者修改且版本 `>=3.9` 的 `/usr/bin/python3`，將 helper trust anchor 驗證過的 wheelhouse 以固定 `pip install --isolated --no-index --target` 安裝到 root-owned staging，並產生固定 Python entrypoint 後 atomic publish。
- 原因：替代手段維持 typed XPC contract、offline pinned payload、root ownership、無 symlink、無 network `pip`、digest 驗證、atomic publish 與結構化失敗語意，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`；因此依 blocker triage 的機制替換分支記錄後繼續。

#### 2026-07-26 22:24 — dev-signed build 改用 SMJobBless 安裝 helper
- 類別：deviation
- 任務：7.3
- 內容：原設計使用 `SMAppService.daemon(plistName:)` 註冊 bundled LaunchDaemon；本機 macOS 26.5 SDK 明定含 LaunchDaemon 的 App 必須 notarized，實測 Apple Development 簽署的 App 無論位於 `/tmp` 或 `/Applications`，`SMAppService.status` 都回傳 `.notFound`。依使用者確認的 dev-certificate-only 發佈邊界，改以仍支援 macOS 13+ 的 `SMJobBless` 完成管理員核准、helper 安裝與 launchd 註冊。
- 原因：替代手段只更換 privileged helper 的安裝／註冊機制，維持既有 typed XPC contract、caller code signature／Team ID 驗證、`TunnelLeaseID` ownership、root-owned offline runtime integrity、結構化失敗與 uninstall／cleanup 驗收標準，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`；因此依 blocker triage 的機制替換分支記錄後繼續。

### 2026-07-27 add-package-app-script

#### 2026-07-27 20:36 — Universal helper metadata 改由單一 architecture slice 擷取

- 類別：deviation
- 任務：3.3
- 內容：原設計直接對 universal embedded helper 執行 `otool -X -s __TEXT __info_plist | xxd -r -p`，會把 architecture address 欄位與 little-endian 32-bit word 順序一起解碼而產生無效 plist。改為先以 `lipo -thin "$(uname -m)"` 擷取目前 host architecture slice，再以 `awk` 移除 address、將每個 word 正規化為 byte order，最後交由既有 `xxd` 流程解碼。
- 原因：此替代手段仍以 built embedded helper 作為 oracle，且不改變可觀察行為、interface／資料形狀、失敗模式或驗收標準；不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

### 2026-07-27 fix-map-sidebar-control-layout

#### 2026-07-27 21:27 — 以 layout probe 取代 production NSButton collector
- 類別：deviation
- 任務：2.1
- 內容：`NSHostingView<LocationMapView>` 中的 SwiftUI production `Button` 不會 materialize 成可由 AppKit view tree 遍歷的 `NSButton`；保留 `TestingActionButton` 專用型別驗證 marker，production button frame 則改由每顆按鈕背景的 DEBUG-only `TestingLayoutRegionView` probe 量測，仍驗證側欄邊界、按鈕互不重疊、同列間距、主要操作 baseline 與 button-vs-status-region 不相交。
- 原因：原 design 指定的 production `NSButton` collector 在目標 SwiftUI/AppKit hosting hierarchy 無法取得任何 production button。替代方式只更換測試量測機制，不改變可觀察布局、interface／資料形狀、失敗模式或驗收標準，且不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

### 2026-07-27 recover-dropped-device-tunnel

#### 2026-07-27 12:40 — 實機 acceptance 暫無 USB 裝置
- 類別：deviation
- 任務：4.4
- 內容：已執行 `system_profiler SPUSBDataType` 與 App 實際 runtime 的 `pymobiledevice3 usbmux list --usb`，結果均未找到 USB iPhone；`xcrun devicectl list devices` 僅顯示 paired 裝置。因此未執行至少 5 分鐘或 250 次連續 route update，也未執行實機 tunnel termination injection；deterministic boundary tests 已涵蓋單次 recovery 與診斷事件，但不宣稱替代實機 acceptance。
- 原因：目前執行環境沒有可供 App 透過 usbmuxd 使用的 USB iPhone，無法安全完成任務要求的實機操作；此項保持未完成，待接上 USB iPhone 後續跑。

#### 2026-07-27 13:41 — 實機長時間路線已補跑
- 類別：deviation
- 任務：4.4
- 內容：前一筆 USB 環境阻塞已解除；使用 `Emily iPhone 14 Pro`、iOS `26.5.2`、USB 連線，從 13:35:35 至 13:40:42 執行同一 route session，共 5 分 7 秒，`location.set_requested` 與 `location.set_succeeded` 均為 298 次，且 failure／recovery／interrupted event 為 0。實機受控 tunnel termination injection 未執行，沒有宣稱該案例通過；單次 recovery 與完整 diagnostic sequence 由 deterministic boundary tests 驗證。
- 原因：長時間 route update 已符合實機 acceptance 門檻；目前沒有不影響使用者裝置與 privileged helper ownership 的安全實機 termination hook，因此保留設計允許的 deterministic boundary test 路徑。

### 2026-07-27 show-confirmed-iphone-route-marker

#### 2026-07-27 18:10 — 實機驗收等待 USB tunnel helper 核准
- 類別：open-question
- 任務：3.3
- 內容：正常 Apple Development 簽章 build 已成功，並已啟動 app；UI 顯示「需要管理員核准 USB tunnel helper」，需由使用者確認是否允許點擊「核准 Helper」並完成可能出現的系統授權，之後才能連接 `Cash iPhone 17 Pro` 執行 route 與目視驗收。
- 原因：核准 helper 會建立或啟用具持續權限的系統元件，依 Computer Use confirmations policy 必須在實際操作當下取得使用者明確同意，不能由實作流程自行假設授權。

#### 2026-07-27 18:17 — Helper 已核准，等待人工完成地圖目視驗收
- 類別：open-question
- 任務：3.3
- 內容：使用者已完成 USB tunnel helper 核准，先前授權問題已解決；app 已確認 `Emily iPhone 14 Pro・iOS 26.5.2` 就緒，但 Computer Use 在地圖選點後反覆因 `SkyComputerUseService` 的 `EXC_BREAKPOINT (SIGTRAP)` 中斷，需由使用者在仍正常執行的 app 中完成 route 並回報 marker 顯示、移動、pause、stop與手動 camera ownership的目視結果。
- 原因：產品 app 與 tunnel/helper 程序均持續正常執行，故障侷限於外部 UI 控制工具；Computer Use skill 禁止在未經使用者指定時改用 AppleScript、System Events 或其他 UI 注入技術，因此不能自行以替代控制工具完成最後互動。

#### 2026-07-27 18:28 — 實機驗收完成
- 類別：open-question
- 任務：3.3
- 內容：先前兩筆 open question 均已解決。使用 `Emily iPhone 14 Pro・iOS 26.5.2` 與正常 Apple Development 簽章 build 完成 route 目視驗收；「iPhone 模擬位置」可與 A／B／Mac marker區分，會隨confirmed update移動，pause保持，stop成功後移除，手動移動地圖後不會因marker更新自動重新置中。驗收中發現 A 與 iPhone 起點重疊時受 MapKit collision layout抑制，已以 `.required` display priority與`.none` collision mode修正，使用者重驗確認通過。
- 原因：記錄實際裝置、iOS版本、完整驗收結果，以及先前 open question 的最終解決狀態，作為task 3.3的驗證證據。

### 2026-07-27 show-mac-location-on-device-ready

#### 2026-07-27 10:38 — 以臨時 bundle identity 驗證首次定位授權
- 類別：deviation
- 任務：13
- 內容：正式 `com.cash.iPhoneLocationMove` 已有 Core Location grant，且此 macOS 不支援以 `tccutil reset Location` 重設；acceptance 改以 `/tmp` 內兩個臨時簽署 bundle identity 分別驗證首次允許與拒絕 prompt，正式 bundle、原始碼與交付行為均不變。
- 原因：此替代方式仍直接執行相同 production code、系統 Core Location 授權流程與 USB ready lifecycle，能保留觀察行為、interface、失敗模式與驗收標準，且不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

#### 2026-07-27 10:44 — 首次授權改採混合 acceptance
- 類別：deviation
- 任務：13
- 內容：臨時 bundle identity 仍未顯示獨立 Core Location prompt，因此 acceptance 最終以正式 signed app 驗證 USB ready、真實座標 marker、初始置中、搜尋與模擬控制可用；`notDetermined` prompt 呼叫、允許、拒絕、service-disabled、晚到結果、手動 camera 與 route replay 則以可控制 production boundary tests 驗證。
- 原因：macOS 在此開發簽署環境持續沿用既有定位 grant，無法在不修改系統 location database 的前提下重現全新 prompt；混合 live 與 deterministic boundary 證據保留相同觀察行為、interface、失敗模式與驗收標準，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

### 2026-07-30 preserve-map-camera-on-click

#### 2026-07-30 09:37 — 停用測試視窗動畫以避開 AppKit crash
- 類別：deviation
- 任務：3.2
- 內容：原定的完整 `xcodebuild test` 在 macOS 26.6 關閉 SwiftUI reset confirmation sheet 時，於 AppKit 的 `NSSheetMoveHelper`／`AppKitDialogBridge` 發生 `EXC_BAD_ACCESS`；改以 `NSAutomaticWindowAnimationsEnabled=NO` 執行相同完整 test suite。
- 原因：crash stack 未包含本次地圖程式碼，且個別排程測試重跑通過；停用測試程序的視窗動畫只替換驗證環境機制，不改變產品 contract、測試斷言或使用者可見行為，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

#### 2026-07-30 09:59 — 分割 AppKit sheet 測試程序
- 類別：deviation
- 任務：3.2
- 內容：停用視窗動畫後，單一 reset sheet 測試可通過，但完整 suite 在同一 test host 連續開關不同 SwiftUI sheets 時仍於相同 AppKit stack crash；因此把完整 suite 等價分割為非 `ContentViewTests`、不開 sheet 的 `ContentViewTests`，以及各 reset sheet 測試的獨立 `xcodebuild test` 程序。
- 原因：分割只隔離 macOS 26.6 的 AppKit test-host lifecycle 缺陷，所有測試案例與斷言仍執行，未改變功能 contract、驗收範圍或使用者可見行為，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

### 2026-07-31 fix-repeat-search-result-selection

#### 2026-07-31 07:54 — View red verification 延後至 model API 可編譯後
- 類別：deviation
- 任務：1.2
- 內容：`parallel_tasks` 同時新增 `LocationMapModelTests.swift` 與 `ContentViewTests.swift` 的 red tests，但 Xcode test target 會編譯全部 test sources，因此 task 1.1 對尚未存在的 `selectSearchResult(_:)` 呼叫先造成 compile red，使 task 1.2 無法獨立進入 view assertion。保留兩組測試，先完成 task 2.1 的 model API，再於修改 `LocationMapView.swift` 前執行 task 1.2，確認它因缺少 rendered result action marker／既有一次性 view guard 而失敗。
- 原因：這只替換 red evidence 的執行順序；view 的觀察行為、interface、失敗模式與驗收標準皆不變，且不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

#### 2026-07-31 08:04 — 以 cancellation observer 驗證 view-local 副作用
- 類別：deviation
- 任務：1.2
- 內容：Round 1 reviewers 指出直接套用 model response 不能證明 stale rendered action 未呼叫 view-local cancellation path。`MKLocalSearch` 與 `CLGeocoder` 的 concrete instances 不提供現有可控制 spy 邊界，因此在 `LocationMapView` initializer 加入預設為 no-op 的 internal cancellation observer closures，並由既有 `cancelSearch()` 與 `cancelPreviewAddressLookup()` 呼叫；rendered tests 以 observer baseline 直接驗證 stale action 未進入任何取消路徑，再驗證 response 仍可套用。
- 原因：這是測試觀察機制替換，沿用相同 production cancellation functions，未改變搜尋、preview、錯誤、camera 或使用者可見 contract，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

#### 2026-07-31 08:36 — Cancellation observer seam 收斂為 DEBUG-only
- 類別：deviation
- 任務：4.1
- 內容：延續前一筆 cancellation observer 測試觀察機制，但將 observers 重新命名為 `onSearchCancellationRequested`／`onPreviewAddressCancellationRequested`，並將 stored properties、initializer parameters、assignments 與 invocation 全部限制於 DEBUG build；`design.md` 同步補回此測試 seam 的邊界，Release build 不再包含 no-op observer closures。
- 原因：這是對既有測試觀察機制的可見範圍與命名修正；搜尋、preview、錯誤、camera、interface 的 Release 形狀與使用者可見 contract 不變，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

#### 2026-07-31 08:38 — 以 DEBUG-only initializer overload 取代 conditional parameter list
- 類別：deviation
- 任務：4.1
- 內容：Swift parser 不接受以 `#if DEBUG` 切開既有 initializer parameter list，因此保留不含 observers 的 production initializer，另以 DEBUG-only overload 接收 `onSearchCancellationRequested` 與 `onPreviewAddressCancellationRequested`，再委派至 production initializer。stored closures 與 invocation 仍全部限制於 DEBUG build。
- 原因：這只替換 test-only initializer parameters 的編譯呈現方式；Release interface、使用者可見行為、失敗模式與驗收標準不變，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

### 2026-08-27 add-favorites

#### 2026-08-27 15:13 — Red 階段受環境阻擋
- 類別：deviation
- 任務：1.1、1.2
- 內容：測試檔建立後首次執行 primary verification target 時，Xcode 因 sandbox 無法寫入 DerivedData 而在編譯前失敗；取得額外權限重跑時 production implementation 已先完成，因此未能取得由目標行為缺失導致的有效 Red failure marker。
- 原因：sandbox 的外部 DerivedData 寫入限制使原本的 Red 執行無法進入編譯階段，為完成驗證只能先解除環境阻塞並重跑測試。

### 2026-08-29 fix-device-locked-and-favorites-layout

#### 2026-08-29 17:55 — trust 的 exit-0 錯誤仍需分類
- 類別：deviation
- 任務：3.2
- 內容：原實作只在 `pymobiledevice3` 回傳非零 exit code 時執行失敗分類；實機驗收發現 `lockdown info` 會在未信任且鎖定時把 `Device is password protected. Please unlock and retry` 寫入 standard error，卻仍回傳 exit code 0。替代手段是在 exit code 判斷之外，對兩個輸出串流中的明確鎖定標記，以及 trust 階段的明確授權標記，套用同一個 typed failure 分類。
- 原因：原手段在目前 `pymobiledevice3` CLI 的實際行為下不可行；替代手段維持既有觀察行為、interface、失敗模式與驗收標準，不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

### 2026-09-05 auto-reconnect-after-usb-replug

#### 2026-09-05 21:50 — 側欄 reconnecting 文字改以 layout region 識別碼驗證
- 類別：deviation
- 任務：2.3
- 內容：design Implementation Contract 第 8 點與 tasks 2.3 要求 view 測試「斷言側欄狀態區顯示『正在重新準備裝置…』」與「顯示『模擬已中斷』與『USB 已中斷』」。實測 SwiftUI 在 macOS `NSHostingView` 內把 `Text`／`ProgressView` 標籤直接繪製，不建立可讀取的 `NSView`：`hostingView.accessibilityChildren()` 回傳 0、整個階層唯一的 `NSSimpleLabel` 不屬於側欄狀態區、其 `description` 也不含字串。改為在 `LocationMapView` 的 `reconnecting` 分支加上 `.testingLayoutRegion("sidebar-simulation-reconnecting-region")`，測試斷言該 region 只在 `reconnecting` 出現、失敗後改出現既有的 `sidebar-simulation-error-region`，並直接斷言 production 路徑的 `DeviceFailurePresentation.make(for: .usbDisconnected).title == "USB 已中斷"`（view 的 `simulationFailureText` 走同一條路徑）。「開始與 Reset 控制項 disabled」同樣受此限制：側欄主要動作按鈕的 `NSButton.title` 為空字串（SwiftUI 自行繪製標籤），改以斷言 `workspace-reset-button` 為 disabled 來覆蓋——Reset 與「設定位置」「開始步行路線」共用同一個 `simulationIsBusy(_:)` 判準，這也是既有 busy 狀態矩陣測試的做法——並額外斷言兩個 start 控制項的 region 仍在畫面上、`sidebar-button-stop-simulation` 不存在。
- 原因：要交付的觀察行為不變——`reconnecting` 仍顯示「正在重新準備裝置…」、控制項仍 busy、仍不顯示「停止模擬」、失敗仍顯示「模擬已中斷」與「USB 已中斷」；改變的只是驗證手段。layout region 識別碼是本測試檔既有的慣用做法（既有的「模擬已中斷」也是以 `sidebar-simulation-error-region` 驗證），不需要 design.md 未定義的同步原語、identity/generation 型別或狀態機。

#### 2026-09-05 21:58 — 測試指令需加上停用簽章的旗標
- 類別：deviation
- 任務：3.1
- 內容：README「測試」段記載的 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS'` 在本機以 `Signing certificate "Apple Development: <redacted> (TA9C85UNZL)" ... is not valid for code signing. It may have been revoked or expired.` 失敗，測試無法開始建置。改以同一條指令附加 `CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` 執行，完整 macOS 測試套件回報 268 tests、0 failures。未修改 `project.yml`、簽章設定或 target membership。
- 原因：這是本機開發憑證過期的環境問題，與本 change 的程式碼無關；驗證目標（同一個 scheme 的完整 macOS 測試套件）與其涵蓋範圍完全不變，只是繞過與測試無關的 code signing 步驟。不需要 design.md 未定義的同步原語、identity/generation 型別或狀態機。

#### Follow-up suggestions

- `iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift` 的 `testDisconnectAfterStatusProbeCancelsRecoveryBeforeRestart` 與 `testQuitDuringCandidateTunnelStartCleansCandidateWithoutPublishingSuccess` 是 pre-existing flaky：兩者都以單一 `await Task.yield()` 當作「對手 task 已推進到某個 await」的屏障，實際排程順序不保證。在本 change 任何程式碼改動之前的 baseline 上重跑五次，即出現 0～3 個失敗（失敗訊息為 `.set` 或 `.stopTunnel` 事件次數 2 vs 1）；套用本 change 後失敗率相同。範圍外依據：這兩個案例不在本 change 的 `tasks.md` 交付目標內，其不穩定成因是既有測試的同步手法而非 `exited` 分類或自動重備行為。建議改以明確的 boundary 屏障（例如既有的 `waitForPendingTunnelStart()`／`waitForPendingTunnelStop()` 模式）取代 `Task.yield()`。

#### 2026-09-05 22:05 — 實機驗證未執行「路線中拔除後停止模擬」這條 regression
- 類別：deviation
- 任務：3.2
- 內容：task 3.2 的 `regression` 列了兩條手動確認，其中「路線執行中拔除、插回後按停止模擬應直接回到未啟用狀態」未執行。使用者實測完 primary target（拔插後按一次開始即成功）與「未插回即開始」後，明確表示第三條不是重點、當作正常。已執行的兩條在 `~/Library/Logs/iPhoneLocationMove/diagnostic.jsonl` 留下完整證據：13:59:22–13:59:32 為 `tunnel.status_probed state=exited` → `usb.disconnected source=tunnel_exited` → `transport.recovery_failed`（一次）→ `location.set_failed failure=usbDisconnected` → `simulation.reconnect_started trigger=start` → `session.ready generation=3` → `simulation.reconnect_succeeded` → `point.started`（同一 sessionID，無中斷畫面）；13:59:57–14:00:23 為未插回時 `simulation.reconnect_failed failure=usbDisconnected` → `point.start_failed failure=usbDisconnected`，插回後再按一次即 `generation=5` 的 `point.started`。
- 原因：這是使用者對驗證範圍的明確決定，不是實作取捨。該條路徑的自動測試涵蓋仍完整（`SimulationStoreTests` 的 `testStopClearDisconnectReconnectsOnceAndCountsAsClearSuccess`、`testRunningRouteProducerFailureNeverReconnects`，以及 `DisconnectReconnectIntegrationTests.testReconnectClearFailureIsRecoveredByStoppingAgain`），缺的只是實機端到端確認。

#### 2026-09-05 22:05 — 實機驗證用的 build 需要 -allowProvisioningUpdates
- 類別：deviation
- 任務：3.2
- 內容：本機 7 張 Apple Development 憑證全部 `CSSMERR_TP_CERT_REVOKED`。以停用簽章的 build 啟動 App 時，`SMJobBless` 以 `helper_approval.unavailable`／`CFErrorDomainLaunchd error 4` 拒絕授權，因為已安裝 helper 的 `SMAuthorizedClients` 要求 `anchor apple generic and certificate leaf[subject.OU] = "2LRM76M575"`，ad-hoc 簽章無法滿足。改以 `xcodebuild build -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates` 讓 Xcode 自動簽發新憑證後，App 與內嵌 helper 皆為 `TeamIdentifier=2LRM76M575`，helper 授權通過並進入 `session.ready`。
- 原因：純屬本機憑證環境問題，與本 change 程式碼無關；未修改 `project.yml`、entitlements、簽章設定或 `SMAuthorizedClients`／`SMPrivilegedExecutables` 需求，交付行為不變。

### 2026-10-27 fix-ios-27-2-classic-tunnel

#### 2026-10-27 21:31 — 刪除而非改寫 macOS 26 probe 測試
- 類別：deviation
- 任務：1.1
- 內容：design.md Decision 5 將 `testMacOS13Through26KeepsClassicTunnelCapability` 列為「移除 host-version 輸入」；實作改為整個刪除該測試，並一併刪除只供它使用的 `classicCompatibleRuntime` stub 與 `RuntimeHarness.macOS26`／`macOS27` 常數。
- 原因：移除 `hostOperatingSystemVersion` 後，該測試的 stub、輸入與預期 probe 序列與 `testCompatibleExistingInstallationUsesLockdownTunnelProbeWithoutCreatingVenv` 完全相同，保留只會是重複斷言；design 的同一段已允許「改寫或移除」，所驗證的 lockdown probe 行為仍由後者涵蓋。
