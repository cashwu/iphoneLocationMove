## 1. 側欄布局修正

- [x] 1.1 在 `iPhoneLocationMove/Features/Map/LocationMapView.swift` 新增 file-private `mapSidebarPrimaryActionLayout()`，把「到 Mac 位置」與 `resetControl` 收進 spacing 8 的 top-level 操作群組，並將所有單列按鈕（含 transient route failure 的「重試」）套用填滿 row、靠左對齊的共同布局；動態搜尋結果維持 full-width plain row，搜尋／清除、設為 A／B、暫停／繼續等多按鈕 row 明確設為 spacing 8 且靠左，確認按鈕 action、role、disabled expression 與 identifier 未變。
- [x] 1.2 在 `iPhoneLocationMove/Features/Map/LocationMapView.swift` 新增 DEBUG-only `TestingActionButton: NSButton`，使其零 intrinsic size、不可接受且拒絕 first responder；將所有 `TestingActionMarker` 使用點限制為零尺寸並禁止 hit testing，設定空標題、無 border、無 focus ring、透明且非 accessibility element，同時保留 `identifier`、`isEnabled`、`isOn`、`action` 與既有 Reset 確認 seam。
- [x] 1.3 在 `iPhoneLocationMove/Features/Map/LocationMapView.swift` 新增 DEBUG-only `TestingLayoutRegionView: NSView` 與對應 `NSViewRepresentable`，並為速度、模擬狀態、錯誤與裝置就緒文字加上無 intrinsic size、不可 focus／hit test、無繪製且非 accessibility element 的 layout probe background，讓 hosting test 依具體型別讀取實際區域 frame，並確認 probe 不改變 production layout 或 accessibility。

## 2. Hosting-view 布局 regression

- [x] 2.1 在 `iPhoneLocationMoveTests/ContentViewTests.swift` 新增 frame 轉換與 collector helper：依 `TestingActionButton` 型別區分共享 identifier 的 marker 與 production `NSButton`，並依 `TestingLayoutRegionView` 型別收集狀態區域；以 1 pt tolerance 驗證可見按鈕 frame 位於 320 pt 側欄邊界內、互不重疊、不與可見狀態區域相交、同列至少相距 8 pt，且單列主要操作共用左側 baseline。
- [x] 2.2 在 `iPhoneLocationMoveTests/ContentViewTests.swift` 新增 disconnected 初始 rendered hierarchy 測試；不執行「到 Mac 位置」或 `Reset` 即驗證所有當前可見按鈕與裝置就緒文字的位置，並直接驗證每個 `TestingActionButton` 零寬、零高、透明、無 focus ring、不可接受且拒絕 first responder、非 accessibility element。
- [x] 2.3 在 `iPhoneLocationMoveTests/ContentViewTests.swift` 只建立一次 connected `NSHostingView<LocationMapView>`，依序驅動同一個 observed `SimulationStore` 從 idle 進入 busy、route running、route paused 再進入 stopping failure；每次等待同一 hierarchy invalidation／layout 後重跑完整 production button、主要操作 baseline、狀態區域與 marker oracle，route paused 以有 timeout 的條件同時等待 model phase 與 `sidebar-button-resume-route` materialize，並確認代表性的速度、模擬狀態、錯誤文字以及 pause／resume／stop probe 存在。
- [x] 2.4 保留並執行 `iPhoneLocationMoveTests/ContentViewTests.swift` 現有 Reset confirmation、busy disabled 與 clear failure tests，證明 layout probe、marker subclass 與按鈕布局修正未改變行為或繞過確認。

## 3. 驗證

- [x] 3.1 執行 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS' -only-testing:iPhoneLocationMoveTests/ContentViewTests`，確認新增布局測試與既有 Reset／定位控制 hosting-view tests 全部通過。
- [x] 3.2 執行 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS'`，確認完整 test suite 通過；以 DEBUG build 在 320 pt 側欄寬度檢視 disconnected、connected、busy 與 clear failure 四種畫面，確認所有按鈕無重疊、越界或 marker 外框。
