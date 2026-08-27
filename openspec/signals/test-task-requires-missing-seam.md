---
id: test-task-requires-missing-seam
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-08-27
last_seen: 2026-08-27
links:
  - openspec/changes/add-favorites/reviews/propose-r1.md
---
# Task 規劃的測試需要不存在的注入 seam

tasks 規劃測試案例時必須確認現有 API surface 可撰寫該測試；若案例需要 private state 的 seed／注入 seam 而 design 未定義該 seam，該案例不可行。應改用 codebase 既有慣例（例如對 generation 型別直接做型別層斷言）或先在 design 明定 seam，不得由 task 隱含引入新機制。

## Occurrences

- 2026-08-27 — `add-favorites` — `cash-propose` Round 1：task 1.2 原要求 model-level 的「generation 耗盡丟出 identityExhausted」案例，但 `mapSearchGeneration` 為 `@Published private(set)` 且無 seed 注入；改為 MapSearchGeneration(rawValue: .max).advanced() 型別層斷言（與 DeviceLocationClientTests 慣例一致）。
