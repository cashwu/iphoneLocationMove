---
id: actor-reentrant-recovery-generation-gate
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/recover-dropped-device-tunnel/reviews/propose-r1.md
---
# Actor reentrant recovery 缺少 generation gate

跨多個 `await` 的 transport recovery transaction 必須在每個外部 side effect 前後重新驗證 captured logical generation 與 device identity；只在入口檢查會讓 disconnect、quit 或 reconnect 插入後的舊 recovery 建立資源或重播 stale mutation。

## Occurrences

- 2026-07-27 — `recover-dropped-device-tunnel` — `cash-propose` Round 1：tunnel recovery 最初未在 status、stop、start、replay 與 commit 邊界重新驗證 session ownership。
