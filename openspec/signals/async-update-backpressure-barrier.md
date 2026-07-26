---
id: async-update-backpressure-barrier
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-26
last_seen: 2026-07-26
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
  - openspec/changes/add-macos-location-simulator/reviews/propose-r3.md
---
# Async update 缺少 backpressure 與實體狀態 barrier

週期性 mutation 必須限制 in-flight 數、coalesce pending 值，並在 pause／clear 等操作確認外部實體狀態；只忽略 stale UI completion 不能阻止舊 mutation 影響裝置。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：route tick 最初可能累積，pause 後舊座標仍可套用到 iPhone。
