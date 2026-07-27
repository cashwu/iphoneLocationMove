---
id: annotation-update-camera-effect-replay
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/show-mac-location-on-device-ready/reviews/propose-r1.md
---
# Annotation update 重播既有 camera effect

Map render state 與 programmatic camera effect 必須分離；annotation 或 overlay redraw 不得從既有 route／preview snapshot 再次推導並重播 camera 操作，camera effect 應以可消耗 identity 套用一次。

## Occurrences

- 2026-07-27 — `show-mac-location-on-device-ready` — `cash-propose` Round 1：Mac marker 更新最初會讓既有 route 再次執行 `setVisibleMapRect`。
