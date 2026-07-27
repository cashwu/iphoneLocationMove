---
id: programmatic-camera-interaction-misclassification
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/show-mac-location-on-device-ready/reviews/apply-r1.md
---
# Programmatic camera update 誤判為使用者操作

Map camera ownership 必須在執行 programmatic update 時明確標記；只從 delegate callback 或 gesture 狀態推測來源，可能把程式化視角變更誤判為使用者操作，或漏掉真正的 manual interaction。

## Occurrences

- 2026-07-27 — `show-mac-location-on-device-ready` — `cash-apply` Round 1：canvas 最初未在 `setRegion`／`setVisibleMapRect` 期間標記 programmatic ownership。
