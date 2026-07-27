---
id: view-lifecycle-request-deduplication
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/show-mac-location-on-device-ready/reviews/propose-r1.md
---
# View lifecycle 無法保存 request 去重 ownership

若 request contract 要求跨視窗或 view 重建對同一 domain identity 至多執行一次，dedup ledger 必須由更長生命週期的 app／store owner 持有，不能放在 view-local model 或 task identity。

## Occurrences

- 2026-07-27 — `show-mac-location-on-device-ready` — `cash-propose` Round 1：per-generation Mac 定位 ledger 最初會因主視窗重開而遺失。
