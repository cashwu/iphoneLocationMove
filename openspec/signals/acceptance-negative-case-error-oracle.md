---
id: acceptance-negative-case-error-oracle
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-macos-location-simulator/reviews/apply-r2.md
---
# Negative acceptance case 未驗證指定失敗原因

負向 acceptance case不能把任意 error視為通過；runner與case manifest必須驗證該案例指定的 typed error，避免環境、授權或連線錯誤產生假陽性。

## Occurrences

- 2026-07-27 — `add-macos-location-simulator` — `cash-apply` Round 2：endpoint timeout與runtime seal tamper runner一度接受任何 thrown error，且endpoint manifest code與實際 typed `timeout`不一致。
