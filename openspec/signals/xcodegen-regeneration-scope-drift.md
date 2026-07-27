---
id: xcodegen-regeneration-scope-drift
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-package-app-script/reviews/apply-r1.md
---
# XcodeGen regeneration 夾帶非必要 scope drift

只為同步單一 build setting 重新產生 Xcode project 時，必須固定相容 generator 設定並檢查 generated diff；不得把未宣告的 resources、全域 build defaults 或 shared scheme churn 一起納入 change。

## Occurrences

- 2026-07-27 — `add-package-app-script` — `cash-apply` Round 1：XcodeGen 一度把 helper acceptance fixtures、全域 defaults 與 scheme churn 帶入 package-script change。
