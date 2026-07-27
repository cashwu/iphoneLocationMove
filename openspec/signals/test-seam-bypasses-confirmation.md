---
id: test-seam-bypasses-confirmation
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-mac-recenter-and-workspace-reset/reviews/apply-r1.md
---
# 測試 seam 繞過 production 確認邊界

為 hosting 或 automation 測試加入 action seam 時，seam 不得直接呼叫確認後的 mutation 而繞過 production UI 的必要確認；測試應先觸發與可見控制相同的確認入口，驗證確認前狀態不變，再由不可供 production 使用者觸發的測試邊界執行確認。

## Occurrences

- 2026-07-27 — `add-mac-recenter-and-workspace-reset` — `cash-apply` Round 1：Reset hosting marker 曾直接呼叫 `performReset`，繞過 spec 要求的確認對話框，且測試因此未驗證真正的確認順序。
