---
id: design-build-tooling-claim-unverified
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-08-27
last_seen: 2026-08-27
links:
  - openspec/changes/add-favorites/reviews/propose-r1.md
---
# Design 對 build 工具鏈的 claim 未經 repo 核實

design 對專案檔管理或 build 工具鏈的 code-facing claim（例如「pbxproj 為手動維護」「無 generator」）必須先對 repo 實際狀態核實（generator spec、README 的建置流程、歷史 commit），不得憑目錄表象推斷；此類錯誤會直接誤導 tasks 的檔案註冊機制與 diff 驗收判準。

## Occurrences

- 2026-08-27 — `add-favorites` — `cash-propose` Round 1：design 宣稱專案為手動維護的 `project.pbxproj`（無 XcodeGen），但 `iPhoneLocationMove/project.yml` 存在且 README 明定以 xcodegen generate 重新產生專案；tasks 的註冊與 diff 驗收判準因此需整組改寫。
