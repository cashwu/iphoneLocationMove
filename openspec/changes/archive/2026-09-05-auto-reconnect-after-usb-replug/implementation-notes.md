<!-- cash-apply implementation notes | change: auto-reconnect-after-usb-replug | initialized: 2026-09-05 10:00 | no entries below means no deviations or open questions were recorded -->

## 2026-09-05 21:50 — 側欄 reconnecting 文字改以 layout region 識別碼驗證
- 類別：deviation
- 任務：2.3
- 內容：design Implementation Contract 第 8 點與 tasks 2.3 要求 view 測試「斷言側欄狀態區顯示『正在重新準備裝置…』」與「顯示『模擬已中斷』與『USB 已中斷』」。實測 SwiftUI 在 macOS `NSHostingView` 內把 `Text`／`ProgressView` 標籤直接繪製，不建立可讀取的 `NSView`：`hostingView.accessibilityChildren()` 回傳 0、整個階層唯一的 `NSSimpleLabel` 不屬於側欄狀態區、其 `description` 也不含字串。改為在 `LocationMapView` 的 `reconnecting` 分支加上 `.testingLayoutRegion("sidebar-simulation-reconnecting-region")`，測試斷言該 region 只在 `reconnecting` 出現、失敗後改出現既有的 `sidebar-simulation-error-region`，並直接斷言 production 路徑的 `DeviceFailurePresentation.make(for: .usbDisconnected).title == "USB 已中斷"`（view 的 `simulationFailureText` 走同一條路徑）。「開始與 Reset 控制項 disabled」同樣受此限制：側欄主要動作按鈕的 `NSButton.title` 為空字串（SwiftUI 自行繪製標籤），改以斷言 `workspace-reset-button` 為 disabled 來覆蓋——Reset 與「設定位置」「開始步行路線」共用同一個 `simulationIsBusy(_:)` 判準，這也是既有 busy 狀態矩陣測試的做法——並額外斷言兩個 start 控制項的 region 仍在畫面上、`sidebar-button-stop-simulation` 不存在。
- 原因：要交付的觀察行為不變——`reconnecting` 仍顯示「正在重新準備裝置…」、控制項仍 busy、仍不顯示「停止模擬」、失敗仍顯示「模擬已中斷」與「USB 已中斷」；改變的只是驗證手段。layout region 識別碼是本測試檔既有的慣用做法（既有的「模擬已中斷」也是以 `sidebar-simulation-error-region` 驗證），不需要 design.md 未定義的同步原語、identity/generation 型別或狀態機。

## 2026-09-05 21:58 — 測試指令需加上停用簽章的旗標
- 類別：deviation
- 任務：3.1
- 內容：README「測試」段記載的 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS'` 在本機以 `Signing certificate "Apple Development: <redacted> (TA9C85UNZL)" ... is not valid for code signing. It may have been revoked or expired.` 失敗，測試無法開始建置。改以同一條指令附加 `CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` 執行，完整 macOS 測試套件回報 268 tests、0 failures。未修改 `project.yml`、簽章設定或 target membership。
- 原因：這是本機開發憑證過期的環境問題，與本 change 的程式碼無關；驗證目標（同一個 scheme 的完整 macOS 測試套件）與其涵蓋範圍完全不變，只是繞過與測試無關的 code signing 步驟。不需要 design.md 未定義的同步原語、identity/generation 型別或狀態機。

## Follow-up suggestions

- `iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift` 的 `testDisconnectAfterStatusProbeCancelsRecoveryBeforeRestart` 與 `testQuitDuringCandidateTunnelStartCleansCandidateWithoutPublishingSuccess` 是 pre-existing flaky：兩者都以單一 `await Task.yield()` 當作「對手 task 已推進到某個 await」的屏障，實際排程順序不保證。在本 change 任何程式碼改動之前的 baseline 上重跑五次，即出現 0～3 個失敗（失敗訊息為 `.set` 或 `.stopTunnel` 事件次數 2 vs 1）；套用本 change 後失敗率相同。範圍外依據：這兩個案例不在本 change 的 `tasks.md` 交付目標內，其不穩定成因是既有測試的同步手法而非 `exited` 分類或自動重備行為。建議改以明確的 boundary 屏障（例如既有的 `waitForPendingTunnelStart()`／`waitForPendingTunnelStop()` 模式）取代 `Task.yield()`。

## 2026-09-05 22:05 — 實機驗證未執行「路線中拔除後停止模擬」這條 regression
- 類別：deviation
- 任務：3.2
- 內容：task 3.2 的 `regression` 列了兩條手動確認，其中「路線執行中拔除、插回後按停止模擬應直接回到未啟用狀態」未執行。使用者實測完 primary target（拔插後按一次開始即成功）與「未插回即開始」後，明確表示第三條不是重點、當作正常。已執行的兩條在 `~/Library/Logs/iPhoneLocationMove/diagnostic.jsonl` 留下完整證據：13:59:22–13:59:32 為 `tunnel.status_probed state=exited` → `usb.disconnected source=tunnel_exited` → `transport.recovery_failed`（一次）→ `location.set_failed failure=usbDisconnected` → `simulation.reconnect_started trigger=start` → `session.ready generation=3` → `simulation.reconnect_succeeded` → `point.started`（同一 sessionID，無中斷畫面）；13:59:57–14:00:23 為未插回時 `simulation.reconnect_failed failure=usbDisconnected` → `point.start_failed failure=usbDisconnected`，插回後再按一次即 `generation=5` 的 `point.started`。
- 原因：這是使用者對驗證範圍的明確決定，不是實作取捨。該條路徑的自動測試涵蓋仍完整（`SimulationStoreTests` 的 `testStopClearDisconnectReconnectsOnceAndCountsAsClearSuccess`、`testRunningRouteProducerFailureNeverReconnects`，以及 `DisconnectReconnectIntegrationTests.testReconnectClearFailureIsRecoveredByStoppingAgain`），缺的只是實機端到端確認。

## 2026-09-05 22:05 — 實機驗證用的 build 需要 -allowProvisioningUpdates
- 類別：deviation
- 任務：3.2
- 內容：本機 7 張 Apple Development 憑證全部 `CSSMERR_TP_CERT_REVOKED`。以停用簽章的 build 啟動 App 時，`SMJobBless` 以 `helper_approval.unavailable`／`CFErrorDomainLaunchd error 4` 拒絕授權，因為已安裝 helper 的 `SMAuthorizedClients` 要求 `anchor apple generic and certificate leaf[subject.OU] = "2LRM76M575"`，ad-hoc 簽章無法滿足。改以 `xcodebuild build -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates` 讓 Xcode 自動簽發新憑證後，App 與內嵌 helper 皆為 `TeamIdentifier=2LRM76M575`，helper 授權通過並進入 `session.ready`。
- 原因：純屬本機憑證環境問題，與本 change 程式碼無關；未修改 `project.yml`、entitlements、簽章設定或 `SMAuthorizedClients`／`SMPrivilegedExecutables` 需求，交付行為不變。
