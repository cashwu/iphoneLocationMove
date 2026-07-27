<!-- cash-apply implementation notes | change: show-confirmed-iphone-route-marker | initialized: 2026-07-27 18:00 | no entries below means no deviations or open questions were recorded -->

## 2026-07-27 18:10 — 實機驗收等待 USB tunnel helper 核准
- 類別：open-question
- 任務：3.3
- 內容：正常 Apple Development 簽章 build 已成功，並已啟動 app；UI 顯示「需要管理員核准 USB tunnel helper」，需由使用者確認是否允許點擊「核准 Helper」並完成可能出現的系統授權，之後才能連接 `Cash iPhone 17 Pro` 執行 route 與目視驗收。
- 原因：核准 helper 會建立或啟用具持續權限的系統元件，依 Computer Use confirmations policy 必須在實際操作當下取得使用者明確同意，不能由 cash-apply 自行假設授權。

## 2026-07-27 18:17 — Helper 已核准，等待人工完成地圖目視驗收
- 類別：open-question
- 任務：3.3
- 內容：使用者已完成 USB tunnel helper 核准，先前授權問題已解決；app 已確認 `Emily iPhone 14 Pro・iOS 26.5.2` 就緒，但 Computer Use 在地圖選點後反覆因 `SkyComputerUseService` 的 `EXC_BREAKPOINT (SIGTRAP)` 中斷，需由使用者在仍正常執行的 app 中完成 route 並回報 marker 顯示、移動、pause、stop與手動 camera ownership的目視結果。
- 原因：產品 app 與 tunnel/helper 程序均持續正常執行，故障侷限於外部 UI 控制工具；Computer Use skill 禁止在未經使用者指定時改用 AppleScript、System Events 或其他 UI 注入技術，因此不能自行以替代控制工具完成最後互動。

## 2026-07-27 18:28 — 實機驗收完成
- 類別：open-question
- 任務：3.3
- 內容：先前兩筆 open question 均已解決。使用 `Emily iPhone 14 Pro・iOS 26.5.2` 與正常 Apple Development 簽章 build 完成 route 目視驗收；「iPhone 模擬位置」可與 A／B／Mac marker區分，會隨confirmed update移動，pause保持，stop成功後移除，手動移動地圖後不會因marker更新自動重新置中。驗收中發現 A 與 iPhone 起點重疊時受 MapKit collision layout抑制，已以 `.required` display priority與`.none` collision mode修正，使用者重驗確認通過。
- 原因：記錄實際裝置、iOS版本、完整驗收結果，以及先前 open question 的最終解決狀態，作為task 3.3的驗證證據。
