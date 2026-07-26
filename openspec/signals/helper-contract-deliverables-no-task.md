---
id: helper-contract-deliverables-no-task
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-26
last_seen: 2026-07-26
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
---
# Helper contract deliverables 沒有 task

Implementation Contract 若要求 protocol 文件或 fixtures，tasks 必須明列交付路徑並讓 tests 實際使用，不能只要求 helper implementation。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：JSON protocol 文件與 fixtures 最初沒有 backing task。
