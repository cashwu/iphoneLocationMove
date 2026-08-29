# 實機驗收結果

## 2026-08-29 — 鎖定裝置提示

- 裝置：Cash iPhone 17 Pro，iOS 26.6.1
- DDI 階段：先在解鎖狀態卸載 Personalized Developer Disk Image，再鎖定裝置啟動目前 source 的簽章 build。實際錯誤摘要為 `PyMobileDevice3Exception: {'Error': 'DeviceLocked'}`；畫面顯示解鎖並保持螢幕開啟的指引，未顯示 Python traceback 或 Xcode／DDI 修復建議。解鎖後重試可重新掛載 DDI 並完成準備。
- trust 階段：解除裝置與 Mac 的 pairing 後，在鎖定狀態啟動目前 source 的簽章 build。`lockdown info` 實際輸出 `Device is password protected. Please unlock and retry` 且 exit code 為 0；修正後畫面仍顯示解鎖指引，未繼續誤報 Developer Mode。解鎖、重新信任並再次重試後，App 顯示 `Cash iPhone 17 Pro・iOS 26.6.1 已就緒`。
- 恢復狀態：pairing 已恢復，Developer Disk Image 已重新掛載，未啟用模擬定位。
