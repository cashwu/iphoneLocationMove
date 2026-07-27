---
id: test-marker-production-control-identity-collision
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/fix-map-sidebar-control-layout/reviews/propose-r1.md
---
# Test marker 與 production control identity 碰撞

當 DEBUG test marker 與 production control 共用 accessibility identifier 時，測試 collector 必須以不可混淆的型別或結構特徵區分兩者；不得以共享 identifier 排除 marker，否則可能同時漏驗 production control 或讓 marker 斷言取錯節點。

## Occurrences

- 2026-07-27 — `fix-map-sidebar-control-layout` — `cash-propose` Round 1：Reset marker 與 production Reset 共用 `workspace-reset-button`，原 frame oracle 依 identifier 篩選而無法可靠區分。
