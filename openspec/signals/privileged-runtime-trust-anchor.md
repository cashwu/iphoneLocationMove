---
id: privileged-runtime-trust-anchor
type: recurring-finding
status: open
occurrences: 2
first_seen: 2026-07-26
last_seen: 2026-07-27
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
  - openspec/changes/add-macos-location-simulator/reviews/propose-r2.md
  - openspec/changes/add-macos-location-simulator/reviews/apply-r1.md
---
# Privileged runtime 缺少不可替換的 trust anchor

privileged process 安裝或執行 runtime 時，只有 hash、owner 或 mode 不足以證明 payload provenance；trust anchor 必須固定在已驗證簽章的 boundary，並防止 payload 與 manifest 同時替換。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：root-owned tunnel runtime 最初未定義 code-signature provenance 與 immutable digest trust anchor。
- 2026-07-27 — `add-macos-location-simulator` — `cash-apply` Round 1：embedded digest固定wheelhouse與manifest，但未固定`pip --target`產生的實際runtime tree，啟動前無法拒絕額外generated內容。
