---
id: xcode-test-file-target-membership
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/fix-stale-simulation-controls/reviews/propose-r2.md
---
# 新增 Xcode test file 未納入 target membership

在使用明確 `PBXFileReference`、`PBXBuildFile` 與 Sources build phase 的 Xcode 專案中，新增 test source 的 proposal 與 task 必須同步包含 project registration；只建立檔案不會讓 `xcodebuild test` 編譯或執行該測試。

## Occurrences

- 2026-07-27 — `fix-stale-simulation-controls` — `cash-propose` Round 2：新增 `ContentViewTests.swift` 後，初版 artifacts 未把 `project.pbxproj` target registration 納入 scope。
