---
id: privileged-process-lease-cleanup
type: recurring-finding
status: open
occurrences: 3
first_seen: 2026-07-26
last_seen: 2026-07-27
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
  - openspec/changes/add-macos-location-simulator/reviews/propose-r2.md
  - openspec/changes/add-macos-location-simulator/reviews/apply-r1.md
  - openspec/changes/add-macos-location-simulator/reviews/apply-r2.md
---
# Privileged process 缺少 lease 與 crash cleanup

長時間 root process 必須有 caller-bound lease、idempotent start、owner-death cleanup、遺失 reply recovery 與 startup reconcile，不能只依顯式 stop。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：tunnel 最初沒有 App crash、XPC invalidation 或 duplicate start 回收 contract。
- 2026-07-27 — `add-macos-location-simulator` — `cash-apply` Round 1：production startup沒有在start前執行fail-closed reconcile，relaunch可能沿用或疊加stale caller lease。
- 2026-07-27 — `add-macos-location-simulator` — `cash-apply` Round 2：一般 preparation已修正 reconcile，但 transport recovery的 replacement start一度漏掉相同 fail-closed ordering。
