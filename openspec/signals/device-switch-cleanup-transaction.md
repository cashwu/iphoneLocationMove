---
id: device-switch-cleanup-transaction
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-26
last_seen: 2026-07-26
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
---
# Active device switch 缺少 cleanup transaction

切換 selected device 前必須以舊 device identity 完成 stop、clear 與 resource teardown；cleanup 失敗時不能 commit 新 selection 或遺失舊 ownership。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：多裝置 contract 最初未定義 active switch 邊界。
