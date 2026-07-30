<!-- cash-apply implementation notes | change: preserve-map-camera-on-click | initialized: 2026-07-30 09:21 | no entries below means no deviations or open questions were recorded -->

## 2026-07-30 09:37 — 停用測試視窗動畫以避開 AppKit crash
- 類別：deviation
- 任務：3.2
- 內容：原定的完整 `xcodebuild test` 在 macOS 26.6 關閉 SwiftUI reset confirmation sheet 時，於 AppKit 的 `NSSheetMoveHelper`／`AppKitDialogBridge` 發生 `EXC_BAD_ACCESS`；改以 `NSAutomaticWindowAnimationsEnabled=NO` 執行相同完整 test suite。
- 原因：crash stack 未包含本次地圖程式碼，且個別排程測試重跑通過；停用測試程序的視窗動畫只替換驗證環境機制，不改變產品 contract、測試斷言或使用者可見行為，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

## 2026-07-30 09:59 — 分割 AppKit sheet 測試程序
- 類別：deviation
- 任務：3.2
- 內容：停用視窗動畫後，單一 reset sheet 測試可通過，但完整 suite 在同一 test host 連續開關不同 SwiftUI sheets 時仍於相同 AppKit stack crash；因此把完整 suite 等價分割為非 `ContentViewTests`、不開 sheet 的 `ContentViewTests`，以及各 reset sheet 測試的獨立 `xcodebuild test` 程序。
- 原因：分割只隔離 macOS 26.6 的 AppKit test-host lifecycle 缺陷，所有測試案例與斷言仍執行，未改變功能 contract、驗收範圍或使用者可見行為，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。
