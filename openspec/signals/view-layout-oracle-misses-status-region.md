---
id: view-layout-oracle-misses-status-region
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/fix-map-sidebar-control-layout/reviews/propose-r1.md
---
# View layout oracle 漏驗狀態區域

當 spec 要求互動 control 不得覆蓋狀態、錯誤或說明文字時，layout regression oracle 必須同時量測 control 與相關文字區域；只比較 control-vs-control 無法驗證完整的可觀察布局 contract。

## Occurrences

- 2026-07-27 — `fix-map-sidebar-control-layout` — `cash-propose` Round 1：原 frame oracle 只收集 `NSButton`，卻宣稱可驗證按鈕不覆蓋速度、模擬狀態、錯誤與裝置就緒文字。
