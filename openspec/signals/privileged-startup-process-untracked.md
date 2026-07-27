---
id: privileged-startup-process-untracked
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-macos-location-simulator/reviews/apply-r1.md
---
# Privileged process 在啟動完成前沒有可取消 ownership

privileged process launch 與完成 endpoint handshake 之間也必須立即進入可取消、可由 caller invalidation 回收的 ownership；不得持有全域 lock 等待無期限外部輸出，或等成功後才登記 lease。

## Occurrences

- 2026-07-27 — `add-macos-location-simulator` — `cash-apply` Round 1：tunnel process存活但不輸出endpoint時，manager持有lock且尚未登記lease，App crash／XPC invalidation無法保證回收root process。
