---
id: transport-failure-state-unspecified
type: recurring-finding
status: open
occurrences: 2
first_seen: 2026-07-26
last_seen: 2026-07-27
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
  - openspec/changes/recover-dropped-device-tunnel/reviews/propose-r1.md
---
# 執行中 transport failure 沒有狀態轉移

active session 的 timeout、helper exit 或 tunnel death 必須停止 producer，標示外部狀態不確定並定義 recovery；typed error 本身不足以防止 UI 繼續顯示 running。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：mid-route DVT failure 最初沒有進入 interrupted 的 contract。
- 2026-07-27 — `recover-dropped-device-tunnel` — `cash-propose` Round 1：新增 recovery success 例外時未同步修改既有 transport failure 立即 interrupted 的 normative contract。
