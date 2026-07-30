---
id: preview-camera-coordinate-dedup
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-30
last_seen: 2026-07-30
links:
  - openspec/changes/preserve-map-camera-on-click/reviews/propose-r1.md
---
# Preview camera effect 以 coordinate 去重

可被使用者手動操作分隔的 programmatic preview camera intent不能只以coordinate去重；回到相同座標的新使用者要求必須有新的identity，否則舊coordinate會錯誤抑制合法camera effect。

## Occurrences

- 2026-07-30 — `preserve-map-camera-on-click` — `cash-propose` Round 1：原設計保留coordinate-based gate，使「搜尋 A → 點擊 B → 再搜尋 A」的第二次搜尋不會置中。
