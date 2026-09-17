---
id: legacy-runtime-preservation-no-oracle
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-09-17
last_seen: 2026-09-17
links:
  - openspec/changes/fix-ios-27-usb-tunnel/reviews/propose-r1.md
---
# 版本化 runtime 升級未驗證舊內容保持不變

當 requirement 宣告版本化 runtime 與 legacy sibling共存且不得刪除、覆寫或信任舊內容時，測試必須建立帶 sentinel 的舊目錄，驗證 executable來源為目前版本，並比較舊內容與 metadata保持不變；只斷言新 destination path不足以證偽破壞式升級。

## Occurrences

- 2026-09-17 — `fix-ios-27-usb-tunnel` — `cash-propose` Round 1：task 原本只斷言 versioned destination，無法抓到實作先刪除舊 `current` 再正常啟動新 runtime。
