---
id: repository-build-output-not-ignored
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-package-app-script/reviews/apply-r1.md
---
# Repository-local build output 未加入 ignore

新增會在 repository 內產生 App、archive、DMG、DerivedData 或其他大型 generated output 的 build 入口時，必須同步加入精確 ignore 規則，避免產物污染工作樹或被誤提交。

## Occurrences

- 2026-07-27 — `add-package-app-script` — `cash-apply` Round 1：新腳本固定寫入 `build/`，但初版沒有在 `.gitignore` 排除該目錄。
