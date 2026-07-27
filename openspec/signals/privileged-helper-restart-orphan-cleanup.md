---
id: privileged-helper-restart-orphan-cleanup
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-macos-location-simulator/reviews/apply-r2.md
---
# Privileged helper restart 可能遺留 root child

privileged helper若只在記憶體保存長時間 child process ownership，helper自身crash並由launchd重啟後可能無法辨識或回收舊root child；需要明確的restart ownership與acceptance邊界。

## Occurrences

- 2026-07-27 — `add-macos-location-simulator` — `cash-apply` Round 2：App termination與XPC invalidation已有cleanup，但helper自身termination後的新manager沒有舊child ownership資料。
