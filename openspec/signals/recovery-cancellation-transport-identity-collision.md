---
id: recovery-cancellation-transport-identity-collision
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/recover-dropped-device-tunnel/reviews/propose-r2.md
---
# Recovery cancellation 與 transport identity 共用 generation

取消跨`await` recovery transaction的ownership token必須與current tunnel／DVT pair identity分離；若切換或quit為取消recovery而提前遞增transport generation，仍須送往old transport的clear reply會被錯判為stale。

## Occurrences

- 2026-07-27 — `recover-dropped-device-tunnel` — `cash-propose` Round 2：`DeviceTransportGeneration`一度同時負責transport識別與recovery cancellation，破壞old-device clear。
