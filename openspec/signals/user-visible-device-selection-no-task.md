---
id: user-visible-device-selection-no-task
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-26
last_seen: 2026-07-26
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
---
# 使用者可見的裝置選擇沒有 backing task

adapter discovery tests 不等同使用者可操作的 selection UI；裝置名稱、版本、多裝置選擇與未選定 gating 都需要明確 delivery task。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：spec 定義多裝置選擇，但 tasks 最初只覆蓋 adapter discovery。
