<!-- cash-apply implementation notes | change: fix-repeat-search-result-selection | initialized: 2026-07-31 07:50 | no entries below means no deviations or open questions were recorded -->

## 2026-07-31 07:54 — View red verification 延後至 model API 可編譯後
- 類別：deviation
- 任務：1.2
- 內容：`parallel_tasks` 同時新增 `LocationMapModelTests.swift` 與 `ContentViewTests.swift` 的 red tests，但 Xcode test target 會編譯全部 test sources，因此 task 1.1 對尚未存在的 `selectSearchResult(_:)` 呼叫先造成 compile red，使 task 1.2 無法獨立進入 view assertion。保留兩組測試，先完成 task 2.1 的 model API，再於修改 `LocationMapView.swift` 前執行 task 1.2，確認它因缺少 rendered result action marker／既有一次性 view guard 而失敗。
- 原因：這只替換 red evidence 的執行順序；view 的觀察行為、interface、失敗模式與驗收標準皆不變，且不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

## 2026-07-31 08:04 — 以 cancellation observer 驗證 view-local 副作用
- 類別：deviation
- 任務：1.2
- 內容：Round 1 reviewers 指出直接套用 model response 不能證明 stale rendered action 未呼叫 view-local cancellation path。`MKLocalSearch` 與 `CLGeocoder` 的 concrete instances 不提供現有可控制 spy 邊界，因此在 `LocationMapView` initializer 加入預設為 no-op 的 internal cancellation observer closures，並由既有 `cancelSearch()` 與 `cancelPreviewAddressLookup()` 呼叫；rendered tests 以 observer baseline 直接驗證 stale action 未進入任何取消路徑，再驗證 response 仍可套用。
- 原因：這是測試觀察機制替換，沿用相同 production cancellation functions，未改變搜尋、preview、錯誤、camera 或使用者可見 contract，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

## 2026-07-31 08:36 — Cancellation observer seam 收斂為 DEBUG-only
- 類別：deviation
- 任務：4.1
- 內容：延續前一筆 cancellation observer 測試觀察機制，但將 observers 重新命名為 `onSearchCancellationRequested`／`onPreviewAddressCancellationRequested`，並將 stored properties、initializer parameters、assignments 與 invocation 全部限制於 DEBUG build；`design.md` 同步補回此測試 seam 的邊界，Release build 不再包含 no-op observer closures。
- 原因：這是對既有測試觀察機制的可見範圍與命名修正；搜尋、preview、錯誤、camera、interface 的 Release 形狀與使用者可見 contract 不變，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

## 2026-07-31 08:38 — 以 DEBUG-only initializer overload 取代 conditional parameter list
- 類別：deviation
- 任務：4.1
- 內容：Swift parser 不接受以 `#if DEBUG` 切開既有 initializer parameter list，因此保留不含 observers 的 production initializer，另以 DEBUG-only overload 接收 `onSearchCancellationRequested` 與 `onPreviewAddressCancellationRequested`，再委派至 production initializer。stored closures 與 invocation 仍全部限制於 DEBUG build。
- 原因：這只替換 test-only initializer parameters 的編譯呈現方式；Release interface、使用者可見行為、失敗模式與驗收標準不變，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。
