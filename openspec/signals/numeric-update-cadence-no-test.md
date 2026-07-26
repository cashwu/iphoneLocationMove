---
id: numeric-update-cadence-no-test
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-26
last_seen: 2026-07-26
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
---
# 數值 update cadence 沒有可控制時間的測試

spec 中「約每秒」之類的數值 acceptance criterion 需要 controllable clock 與 scheduler assertion，僅測距離公式或 timer delay 不能證明 cadence。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：一秒 location update cadence 最初沒有直接測試。
