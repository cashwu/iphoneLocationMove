---
id: crash-relaunch-cleanup-ownership
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-26
last_seen: 2026-07-26
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r4.md
---
# Crash 後沒有持久 cleanup ownership

外部 mutation 可能在 App crash 或強制退出後殘留；若沒有持久記錄最小 device cleanup ownership，relaunch 無法保證在 ready 前對同一裝置 clear。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 4：發現 tunnel reconcile 不等同裝置模擬狀態 recovery。
