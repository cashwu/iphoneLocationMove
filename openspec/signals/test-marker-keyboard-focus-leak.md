---
id: test-marker-keyboard-focus-leak
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/fix-map-sidebar-control-layout/reviews/propose-r1.md
---
# Test marker 仍可取得鍵盤 focus

不可見的 AppKit test control 除了零尺寸、透明與禁止 pointer hit testing，還必須明確拒絕 first responder、key-view 與 accessibility focus；隱藏 focus ring 不能證明 control 不會攔截鍵盤操作。

## Occurrences

- 2026-07-27 — `fix-map-sidebar-control-layout` — `cash-propose` Round 1：原設計只要求 marker 零尺寸、透明、`focusRingType = .none` 與 `.allowsHitTesting(false)`，未禁止 `NSButton` 成為 first responder。
