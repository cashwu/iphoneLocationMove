---
id: diagnostic-sensitive-detail-no-redaction
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/recover-dropped-device-tunnel/reviews/propose-r1.md
---
# Diagnostic detail 沒有敏感值 redaction

將 exception message 或 process stderr 寫入持久 diagnostic log 時，截長與移除換行不等同 redaction；若 contract 禁止 endpoint、座標或其他敏感值，必須在寫入前產生安全欄位或明確遮蔽，並用含敏感值的 deterministic fixture 驗證。

## Occurrences

- 2026-07-27 — `recover-dropped-device-tunnel` — `cash-propose` Round 1：tunnel stderr 與 backend detail 最初依賴不會移除 endpoint／座標的既有 sanitizer。
