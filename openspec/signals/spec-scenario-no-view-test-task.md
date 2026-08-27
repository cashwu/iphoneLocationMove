---
id: spec-scenario-no-view-test-task
type: recurring-finding
status: open
occurrences: 2
first_seen: 2026-07-27
last_seen: 2026-08-27
links:
  - openspec/changes/add-mac-recenter-and-workspace-reset/reviews/propose-r1.md
  - openspec/changes/add-favorites/reviews/apply-r6.md
---
# Spec 的 view 層 scenario 與 Example 沒有測試 task

spec scenario 或 Example 涉及 view 層可觀察行為（toggle 歸位、按鈕 disabled、警語分支、失敗顯示保留）時，tasks 不能只列 model 層測試；必須有對應 view 層測試 task（hosting-view 模式）或把行為抽成可測純函式，否則 Example 無法驗收。

## Occurrences

- 2026-07-27 — `add-mac-recenter-and-workspace-reset` — `cash-propose` Round 1：Example「往返循環關閉」與警語分支、busy disabled、clear 失敗不掩蓋等 scenario 最初無任何對應測試 task。
- 2026-08-27 — `add-favorites` — `cash-apply` Round 6：delete 後 preview／simulation 已驗證，但 map annotation 的 rendered boundary oracle 仍缺失。
