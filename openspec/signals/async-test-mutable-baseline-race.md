---
id: async-test-mutable-baseline-race
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/show-confirmed-iphone-route-marker/reviews/apply-r1.md
---
# Async test 使用可變 reference 作為比較基準

非同步測試若要比較更新前後狀態，必須在觸發更新前將基準值複製為不可變 snapshot；更新後再從同一個可變 reference讀取舊值會產生排程競態，使測試誤等下一次變化或偶發逾時。

## Occurrences

- 2026-07-27 — `show-confirmed-iphone-route-marker` — `cash-apply` Round 1：rendered-hierarchy test在route tick後才從同一annotation instance讀取初始longitude，device completion若先更新該instance就會污染比較基準。
