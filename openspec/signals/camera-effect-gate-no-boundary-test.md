---
id: camera-effect-gate-no-boundary-test
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/show-mac-location-on-device-ready/reviews/apply-r1.md
---
# Camera effect gate 缺少直接 boundary test

以 identity 或 ownership 控制 programmatic camera effect 時，測試必須直接執行 effect gate；只驗證上游 model state 無法證明 redraw 不重播 camera，也無法證明 programmatic 與 manual interaction 的分類正確。

## Occurrences

- 2026-07-27 — `show-mac-location-on-device-ready` — `cash-apply` Round 1：初版測試只驗證 route identity model state，未執行 canvas camera effect gate。
