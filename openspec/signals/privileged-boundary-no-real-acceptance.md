---
id: privileged-boundary-no-real-acceptance
type: recurring-finding
status: open
occurrences: 2
first_seen: 2026-07-26
last_seen: 2026-07-27
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
  - openspec/changes/add-macos-location-simulator/reviews/apply-r1.md
---
# Privileged boundary 只有 unit contract test

audit token、root ownership、daemon cleanup、runtime tamper 與 uninstall 行為需要隔離的實際 privileged acceptance；fake XPC unit tests 無法證明部署後 boundary。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：privileged helper 最初缺少需管理員核准的真實環境 gate。
- 2026-07-27 — `add-macos-location-simulator` — `cash-apply` Round 1：task 7.3 將 user-space fake harness 與正向 production smoke 合併宣稱完整 privileged adversarial acceptance，未在真實 XPC／SMJobBless boundary驗證負向案例。
