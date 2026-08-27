<!-- cash-apply implementation notes | change: add-favorites | initialized: 2026-08-27 00:00 | no entries below means no deviations or open questions were recorded -->

## 2026-08-27 15:13 — Red 階段受環境阻擋
- 類別：deviation
- 任務：1.1、1.2
- 內容：測試檔建立後首次執行 primary verification target 時，Xcode 因 sandbox 無法寫入 DerivedData 而在編譯前失敗；取得額外權限重跑時 production implementation 已先完成，因此未能取得由目標行為缺失導致的有效 Red failure marker。
- 原因：sandbox 的外部 DerivedData 寫入限制使原本的 Red 執行無法進入編譯階段，為完成驗證只能先解除環境阻塞並重跑測試。
