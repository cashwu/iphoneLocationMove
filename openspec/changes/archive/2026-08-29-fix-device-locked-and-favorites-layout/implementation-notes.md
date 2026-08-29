<!-- cash-apply implementation notes | change: fix-device-locked-and-favorites-layout | initialized: 2026-08-29 12:20 | no entries below means no deviations or open questions were recorded -->

## 2026-08-29 17:55 — trust 的 exit-0 錯誤仍需分類
- 類別：deviation
- 任務：3.2
- 內容：原實作只在 `pymobiledevice3` 回傳非零 exit code 時執行失敗分類；實機驗收發現 `lockdown info` 會在未信任且鎖定時把 `Device is password protected. Please unlock and retry` 寫入 standard error，卻仍回傳 exit code 0。替代手段是在 exit code 判斷之外，對兩個輸出串流中的明確鎖定標記，以及 trust 階段的明確授權標記，套用同一個 typed failure 分類。
- 原因：原手段在目前 `pymobiledevice3` CLI 的實際行為下不可行；替代手段維持既有觀察行為、interface、失敗模式與驗收標準，不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。
