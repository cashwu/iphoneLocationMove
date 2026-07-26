---
id: privileged-process-lease-cleanup
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-26
last_seen: 2026-07-26
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
  - openspec/changes/add-macos-location-simulator/reviews/propose-r2.md
---
# Privileged process 缺少 lease 與 crash cleanup

長時間 root process 必須有 caller-bound lease、idempotent start、owner-death cleanup、遺失 reply recovery 與 startup reconcile，不能只依顯式 stop。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：tunnel 最初沒有 App crash、XPC invalidation 或 duplicate start 回收 contract。
