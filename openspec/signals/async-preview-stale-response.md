---
id: async-preview-stale-response
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-26
last_seen: 2026-07-26
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
  - openspec/changes/add-macos-location-simulator/reviews/propose-r4.md
---
# Async preview response 未隨 ownership 變更失效

search 或 directions response 必須綁定 query／endpoint generation；任何取代 preview ownership 的操作都要失效舊 request，而不只是送出新 query。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：MapKit response 最初可能覆寫較新的 query 或 A／B；Round 4 進一步發現 map click path。
