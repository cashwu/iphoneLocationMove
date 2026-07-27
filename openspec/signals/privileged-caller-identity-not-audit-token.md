---
id: privileged-caller-identity-not-audit-token
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-macos-location-simulator/reviews/apply-r1.md
---
# Privileged caller trust 未綁定 connection audit token

privileged XPC boundary宣稱驗證connection audit identity時，Security trust decision必須使用connection-bound audit token或等價不可混淆identity；只以PID查`SecCode`，但未把擷取的EUID與audit session納入驗證，不能支撐相同安全宣稱。

## Occurrences

- 2026-07-27 — `add-macos-location-simulator` — `cash-apply` Round 1：helper從connection保存PID／EUID／audit session，但Security驗證只使用PID，與artifacts的audit-token binding宣稱不符。
