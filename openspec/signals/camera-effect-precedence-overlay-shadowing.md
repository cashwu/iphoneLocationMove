---
id: camera-effect-precedence-overlay-shadowing
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-30
last_seen: 2026-07-30
links:
  - openspec/changes/preserve-map-camera-on-click/reviews/propose-r1.md
---
# 既有 overlay 存在遮蔽新的 camera intent

Camera precedence必須依本輪是否實際套用effect判斷，不能只依annotation或overlay是否存在；已消耗identity對應的render物件不得永久遮蔽後續新的使用者camera intent。

## Occurrences

- 2026-07-30 — `preserve-map-camera-on-click` — `cash-propose` Round 1：route overlay存在時原Coordinator永遠停在route分支，已消耗的route identity仍會遮蔽新的搜尋置中。
