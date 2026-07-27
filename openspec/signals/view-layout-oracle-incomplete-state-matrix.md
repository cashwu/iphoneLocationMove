---
id: view-layout-oracle-incomplete-state-matrix
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/fix-map-sidebar-control-layout/reviews/apply-r1.md
  - openspec/changes/fix-map-sidebar-control-layout/reviews/apply-r3.md
---
# View layout oracle 的狀態矩陣不完整

條件式 UI 的 layout regression 必須在每個宣告涵蓋的狀態執行完整 oracle，並要求該狀態應出現的控制；可選的空 expected set、漏掉動態狀態，或只在部分狀態執行 marker／layout 斷言，都會讓測試在布局 contract 失效時仍通過。

## Occurrences

- 2026-07-27 — `fix-map-sidebar-control-layout` — `cash-apply` Round 1 與 3：connected baseline expected set 原為空且未涵蓋 running／paused，補狀態後又漏在 running／paused 重跑 marker oracle。
