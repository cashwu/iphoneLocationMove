---
id: generated-user-state-scope-drift
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-package-app-script/reviews/apply-r1.md
---
# Tool execution 夾帶個人 user-state binary diff

執行 IDE、generator 或驗收工具後，必須從 change 排除與交付無關的個人 workspace、window 或 UI state binary 變更，避免不可審查的使用者狀態被提交。

## Occurrences

- 2026-07-27 — `add-package-app-script` — `cash-apply` Round 1：Xcode 驗收一度修改 tracked `UserInterfaceState.xcuserstate`。
