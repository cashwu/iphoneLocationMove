<!-- cash-apply implementation notes | change: fix-ios-27-2-classic-tunnel | initialized: 2026-10-27 21:28 | no entries below means no deviations or open questions were recorded -->

## 2026-10-27 21:31 — 刪除而非改寫 macOS 26 probe 測試
- 類別：deviation
- 任務：1.1
- 內容：design.md Decision 5 將 `testMacOS13Through26KeepsClassicTunnelCapability` 列為「移除 host-version 輸入」；實作改為整個刪除該測試，並一併刪除只供它使用的 `classicCompatibleRuntime` stub 與 `RuntimeHarness.macOS26`／`macOS27` 常數。
- 原因：移除 `hostOperatingSystemVersion` 後，該測試的 stub、輸入與預期 probe 序列與 `testCompatibleExistingInstallationUsesLockdownTunnelProbeWithoutCreatingVenv` 完全相同，保留只會是重複斷言；design 的同一段已允許「改寫或移除」，所驗證的 lockdown probe 行為仍由後者涵蓋。
