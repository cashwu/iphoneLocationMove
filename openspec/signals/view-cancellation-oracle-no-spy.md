---
id: view-cancellation-oracle-no-spy
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-31
last_seen: 2026-07-31
links:
  - openspec/changes/fix-repeat-search-result-selection/reviews/apply-r1.md
---
# View cancellation regression 沒有觀察 production path

宣稱 stale view action 不會取消 current async operation 的 regression test，必須以 spy 或等價 seam 直接觀察相同 production cancellation path，並提供成功路徑 positive control 證明 seam 已接線；只驗證 model response 仍可套用，無法排除 view 已錯誤呼叫取消。

## Occurrences

- 2026-07-31 — `fix-repeat-search-result-selection` — `cash-apply` Round 1：兩個 stale-action tests 最初只手動套用 model response，沒有觀察 `cancelSearch()` 與 `cancelPreviewAddressLookup()`，即使 view 先取消較新的 operation 仍會通過。
