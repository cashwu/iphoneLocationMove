---
id: error-classification-misses-raw-error-string
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-08-29
last_seen: 2026-08-29
links:
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r1.md
---
# 錯誤分類關鍵字未涵蓋底層原始錯誤字串

以字串比對分類第三方工具的失敗時，關鍵字必須同時涵蓋底層協定回傳的原始錯誤字串與其被包裝後的例外名稱兩種形式。只比對包裝後的名稱，會在輸出落在只印出原始錯誤字典的路徑時漏判，退回顯示與真正原因無關的階段指引。應回該工具原始碼確認兩種形式的實際字面值。

## Occurrences

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — `cash-propose` Round 1：鎖定判定只涵蓋 `passwordrequired`，但 pymobiledevice3 的 lockdown 回傳的原始字串是 `PasswordProtected`，僅在包裝為 `PasswordRequiredError` 後才出現前者。
