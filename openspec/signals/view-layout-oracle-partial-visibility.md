---
id: view-layout-oracle-partial-visibility
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-08-29
last_seen: 2026-08-29
links:
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/apply-r1.md
---
# View layout oracle 只驗證部分可見

當 requirement 要求控制項完整位於可視範圍內時，layout regression oracle 不能只驗證控制項 frame 與 viewport 相交；只剩少量像素可見時也會通過。測試應對 requirement 指定的控制項驗證完整 frame containment，並只保留明確且有限的量測誤差。

## Occurrences

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — `cash-apply` Round 1：側欄測試原本只要求「設定位置」按鈕與 sidebar bounds 相交，無法證偽按鈕被部分推出可視範圍。
