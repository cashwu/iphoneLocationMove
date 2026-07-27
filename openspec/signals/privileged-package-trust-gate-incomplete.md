---
id: privileged-package-trust-gate-incomplete
type: recurring-finding
status: open
occurrences: 2
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-package-app-script/reviews/propose-r1.md
  - openspec/changes/add-package-app-script/reviews/propose-r2.md
  - openspec/changes/add-package-app-script/reviews/apply-r1.md
---
# Privileged package trust gate 未驗證實際雙向 identity

包含 privileged helper 的 package gate 必須對實際 signed App 與 embedded helper 驗證固定 identifiers、固定 Team 與雙向 authorization requirements；只比較兩者 Team 相同或只讀 repository source plist，可能讓無法通過 production authorization 的產物被誤判成功。

## Occurrences

- 2026-07-27 — `add-package-app-script` — `cash-propose` Rounds 1、2：簽署 gate 最初只比較相同 Team，修正後仍一度以 source helper plist 代替 built embedded helper metadata。
- 2026-07-27 — `add-package-app-script` — `cash-apply` Round 1：實作已讀 built metadata，但初版 regression fixture 沒有同時提供正確 source plist，未直接防止未來 source fallback 掩蓋 embedded drift。
