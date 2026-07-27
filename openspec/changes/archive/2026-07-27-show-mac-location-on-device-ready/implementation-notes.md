<!-- cash-apply implementation notes | change: show-mac-location-on-device-ready | initialized: 2026-07-27 09:49 | no entries below means no deviations or open questions were recorded -->

## 2026-07-27 10:38 — 以臨時 bundle identity 驗證首次定位授權
- 類別：deviation
- 任務：13
- 內容：正式 `com.cash.iPhoneLocationMove` 已有 Core Location grant，且此 macOS 不支援以 `tccutil reset Location` 重設；acceptance 改以 `/tmp` 內兩個臨時簽署 bundle identity 分別驗證首次允許與拒絕 prompt，正式 bundle、原始碼與交付行為均不變。
- 原因：此替代方式仍直接執行相同 production code、系統 Core Location 授權流程與 USB ready lifecycle，能保留觀察行為、interface、失敗模式與驗收標準，且不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。

## 2026-07-27 10:44 — 首次授權改採混合 acceptance
- 類別：deviation
- 任務：13
- 內容：臨時 bundle identity 仍未顯示獨立 Core Location prompt，因此 acceptance 最終以正式 signed app 驗證 USB ready、真實座標 marker、初始置中、搜尋與模擬控制可用；`notDetermined` prompt 呼叫、允許、拒絕、service-disabled、晚到結果、手動 camera 與 route replay 則以可控制 production boundary tests 驗證。
- 原因：macOS 在此開發簽署環境持續沿用既有定位 grant，無法在不修改系統 location database 的前提下重現全新 prompt；混合 live 與 deterministic boundary 證據保留相同觀察行為、interface、失敗模式與驗收標準，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。
