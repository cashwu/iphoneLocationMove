---
id: recovery-ownership-event-matrix-gap
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/recover-dropped-device-tunnel/reviews/propose-r3.md
---
# Recovery ownership event matrix 缺少直接邊界測試

跨多個`await`的recovery ownership gate若可被disconnect、reconnect、quit或device switch失效，deterministic suspension tests必須直接覆蓋每種ownership event的代表邊界；只測部分事件不能證明其cleanup與stale-replay規則一致。

## Occurrences

- 2026-07-27 — `recover-dropped-device-tunnel` — `cash-propose` Round 3：recovery suspension matrix最初未直接插入device switch並驗證candidate cleanup與old-device clear。
