---
id: design-risk-premise-unverified
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-08-29
last_seen: 2026-08-29
links:
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r1.md
---
# Design 風險段落的事實前提未經核實

`## Risks / Trade-offs` 以「本次未寫入某處」「不引入新的某類路徑」作為不採取緩解措施的理由時，該前提必須先對實際程式碼路徑核實。前提為假時即使結論碰巧成立，錯誤的理由仍會誤導後續對同一議題的判斷。

## Occurrences

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — `cash-propose` Round 1：design 以「未寫入持久診斷紀錄」為由不做敏感值遮蔽，但失敗 detail 會經 typed 失敗寫入 diagnostic metadata 並落地至使用者的 diagnostic.jsonl。
