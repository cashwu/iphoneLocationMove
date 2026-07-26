---
id: acceptance-environment-precondition-mismatch
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-26
last_seen: 2026-07-26
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r4.md
---
# Acceptance environment 無法滿足測試前提

acceptance task 宣告的實體資源必須足以執行列出的行為；單裝置環境不能驗證需要第二台可選裝置的 switch 流程。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 4：單 iPhone acceptance 一度要求 active-device switch failure。
