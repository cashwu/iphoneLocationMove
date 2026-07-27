---
id: privileged-active-lease-stale-retry
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-macos-location-simulator/reviews/apply-r2.md
---
# Active privileged lease retry 未驗證 process 存活

同一 idempotency key命中 active lease時，必須先確認底層 privileged process仍存活；不得把已退出 process的舊 `.running` snapshot當成有效 lease回傳。

## Occurrences

- 2026-07-27 — `add-macos-location-simulator` — `cash-apply` Round 2：pending ownership refactor一度讓 active same-key fast path直接回傳 snapshot，未處理 process在 `status`前自行退出。
