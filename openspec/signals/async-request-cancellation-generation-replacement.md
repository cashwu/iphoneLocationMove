---
id: async-request-cancellation-generation-replacement
type: recurring-finding
status: open
occurrences: 2
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/show-mac-location-on-device-ready/reviews/propose-r1.md
  - openspec/changes/show-mac-location-on-device-ready/reviews/apply-r1.md
---
# Async request replacement 未完成舊 ownership

以 generation 取代單一 in-flight async request 時，必須先讓舊 request 經 cancellation terminal path 完成並清除 ownership，再啟動最新 generation；只丟棄 stale response 仍可能讓舊 continuation 阻塞新要求。

## Occurrences

- 2026-07-27 — `show-mac-location-on-device-ready` — `cash-propose` Round 1：舊 Core Location continuation 最初可能讓 reconnect generation 收到 concurrent-request error。
- 2026-07-27 — `show-mac-location-on-device-ready` — `cash-apply` Round 1：pre-cancelled Core Location task 一度繞過 typed cancellation terminal mapping。
