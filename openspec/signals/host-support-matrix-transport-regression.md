---
id: host-support-matrix-transport-regression
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-09-17
last_seen: 2026-09-17
links:
  - openspec/changes/fix-ios-27-usb-tunnel/reviews/propose-r1.md
---
# 新 transport 無條件取代既有支援矩陣

針對新 OS 組合修復 transport 時，若專案仍宣告支援較早 host／device 組合，提案必須定義可驗證的適用政策；不能只以新環境的成功證據把所有既有支援組合無條件切到未驗證 transport。

## Occurrences

- 2026-09-17 — `fix-ios-27-usb-tunnel` — `cash-propose` Round 1：原設計讓 macOS 13+ 全部改走只在 macOS 27實測的 native tunnel，可能使既有支援矩陣退化。
