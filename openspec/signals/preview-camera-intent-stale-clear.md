---
id: preview-camera-intent-stale-clear
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-30
last_seen: 2026-07-30
links:
  - openspec/changes/preserve-map-camera-on-click/reviews/propose-r1.md
---
# Preview 清除未同步失效 camera intent

當search開始、clear、Reset或其他preview ownership變更清除render state時，相關camera intent也必須在同一owner內同步失效；否則稍後的redraw或precedence變化可能執行已無preview對應的stale effect。

## Occurrences

- 2026-07-30 — `preserve-map-camera-on-click` — `cash-propose` Round 1：原設計漏列`beginSearch(query:)`清除preview時的camera target transition。
