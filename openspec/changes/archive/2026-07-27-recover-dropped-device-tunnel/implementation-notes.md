<!-- cash-apply implementation notes | change: recover-dropped-device-tunnel | initialized: 2026-07-27 12:15 | no entries below means no deviations or open questions were recorded -->

## 2026-07-27 12:40 — 實機 acceptance 暫無 USB 裝置
- 類別：deviation
- 任務：4.4
- 內容：已執行 `system_profiler SPUSBDataType` 與 App 實際 runtime 的 `pymobiledevice3 usbmux list --usb`，結果均未找到 USB iPhone；`xcrun devicectl list devices` 僅顯示 paired 裝置。因此未執行至少 5 分鐘或 250 次連續 route update，也未執行實機 tunnel termination injection；deterministic boundary tests 已涵蓋單次 recovery 與診斷事件，但不宣稱替代實機 acceptance。
- 原因：目前執行環境沒有可供 App 透過 usbmuxd 使用的 USB iPhone，無法安全完成任務要求的實機操作；此項保持未完成，待接上 USB iPhone 後續跑。

## 2026-07-27 13:41 — 實機長時間路線已補跑
- 類別：deviation
- 任務：4.4
- 內容：前一筆 USB 環境阻塞已解除；使用 `Emily iPhone 14 Pro`、iOS `26.5.2`、USB 連線，從 13:35:35 至 13:40:42 執行同一 route session，共 5 分 7 秒，`location.set_requested` 與 `location.set_succeeded` 均為 298 次，且 failure／recovery／interrupted event 為 0。實機受控 tunnel termination injection 未執行，沒有宣稱該案例通過；單次 recovery 與完整 diagnostic sequence 由 deterministic boundary tests 驗證。
- 原因：長時間 route update 已符合實機 acceptance 門檻；目前沒有不影響使用者裝置與 privileged helper ownership 的安全實機 termination hook，因此保留設計允許的 deterministic boundary test 路徑。
