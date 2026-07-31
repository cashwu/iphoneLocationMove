---
id: stale-view-action-cancels-current-request
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-31
last_seen: 2026-07-31
links:
  - openspec/changes/fix-repeat-search-result-selection/reviews/propose-r1.md
---
# Stale view action 取消 current async request

保留 async ownership 的 view action 必須先通過 current model ownership gate，成功後才能取消 view-local async work；重繪前殘留的 stale action 不得先取消較新的 request，再由 model 拒絕。

## Occurrences

- 2026-07-31 — `fix-repeat-search-result-selection` — `cash-propose` Round 1：搜尋結果 action 原規劃沿用 cancel-before-validation 順序，可能讓重繪前的舊列取消較新的 MapKit search 或 reverse-geocode。
