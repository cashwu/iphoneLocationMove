---
id: route-terminal-state-transitions
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-26
last_seen: 2026-07-26
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
---
# Route terminal state 缺少後續轉移

狀態仍持有外部資源或模擬效果時，即使名為 completed，也必須定義 stop、interrupt、replacement 與 quit 的後續轉移。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：`completed` 仍維持模擬位置，卻未連到 stopping／interrupted。
