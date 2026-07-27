---
id: shell-contract-scenario-no-test-task
type: recurring-finding
status: open
occurrences: 2
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-package-app-script/reviews/propose-r1.md
  - openspec/changes/add-package-app-script/reviews/apply-r1.md
---
# Shell public contract scenario 沒有 backing test task

shell 入口的 path resolution、short aliases 與 fail-before-destructive-action 等 public contract 必須在 tasks 中有對應 deterministic cases；只規劃一般成功／失敗 command shims，無法證明非 root current directory、含空白路徑或 marker 缺失時的安全行為。

## Occurrences

- 2026-07-27 — `add-package-app-script` — `cash-propose` Round 1：初版 tasks 未明列非 root cwd、含空白 fixture path、marker fail-before-clean 與 `-h`／`-v` aliases。
- 2026-07-27 — `add-package-app-script` — `cash-apply` Round 1：contract suite 一度只直接驗證 `-v` 成功路徑，沒有對應的 `--version` 成功案例。
