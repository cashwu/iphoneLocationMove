<!-- cash-apply implementation notes | change: fix-map-sidebar-control-layout | initialized: 2026-07-27 21:19 | no entries below means no deviations or open questions were recorded -->

## 2026-07-27 21:27 — 以 layout probe 取代 production NSButton collector
- 類別：deviation
- 任務：2.1
- 內容：`NSHostingView<LocationMapView>` 中的 SwiftUI production `Button` 不會 materialize 成可由 AppKit view tree 遍歷的 `NSButton`；保留 `TestingActionButton` 專用型別驗證 marker，production button frame 則改由每顆按鈕背景的 DEBUG-only `TestingLayoutRegionView` probe 量測，仍驗證側欄邊界、按鈕互不重疊、同列間距、主要操作 baseline 與 button-vs-status-region 不相交。
- 原因：原 design 指定的 production `NSButton` collector 在目標 SwiftUI/AppKit hosting hierarchy 無法取得任何 production button。替代方式只更換測試量測機制，不改變可觀察布局、interface／資料形狀、失敗模式或驗收標準，且不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。
