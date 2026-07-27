<!-- cash-apply implementation notes | change: add-mac-recenter-and-workspace-reset | initialized: 2026-07-27 18:39 | no entries below means no deviations or open questions were recorded -->

## 2026-07-27 18:54 — Hosting 測試改用既有 marker 邊界
- 類別：deviation
- 任務：3.4
- 內容：原本嘗試由 `NSHostingView` 的 accessibility tree 直接取得並操作 SwiftUI controls，但目前測試環境只公開 repo 既有 `AccessibilityIdentifierMarker` 所建立的 `NSView` 邊界；改以同一既有模式加入零尺寸 action marker，讓 hosting tests 觸發相同的 SwiftUI state 與 action closure。
- 原因：此替代手段只改變測試驅動 UI action 的機制，不改變可觀察行為、interface／資料形狀、失敗模式或驗收標準，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

## 2026-07-27 19:08 — 修正 hosting marker 的確認邊界
- 類別：deviation
- 任務：3.4
- 內容：Round 1 review 證實原 action marker 直接呼叫 `performReset`，實際上繞過確認 contract；現已改為 DEBUG-only、從 accessibility tree 隱藏的 testing marker，Reset marker 只呼叫 `presentResetConfirmation`，confirmation marker 僅在 `isResetConfirmationPresented == true` 時才可執行確認後的 reset，並新增確認前工作區不變的 hosting assertion。
- 原因：保留既有 marker 測試機制，但修正先前 deviation 對 contract 不變的錯誤判斷，使所有 production Reset 入口與 hosting verification 都維持「先確認、後重置」的相同行為邊界。
