---
id: preview-camera-intent-transition-no-test
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-30
last_seen: 2026-07-30
links:
  - openspec/changes/preserve-map-camera-on-click/reviews/propose-r1.md
---
# Preview camera intent transition 沒有 owner-level test

若camera行為取決於搜尋、直接點擊、clear或failure對intent的分類，測試必須直接執行持有該transition的owner；只向下游canvas注入nil或非nil intent無法防止分類或清理path遺漏。

## Occurrences

- 2026-07-30 — `preserve-map-camera-on-click` — `cash-propose` Round 1：原tasks只測Coordinator注入值，未驗證搜尋成功、地圖點擊、clear、Reset與validation failure的intent轉移。
