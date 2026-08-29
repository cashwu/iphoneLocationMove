---
id: spec-delta-internal-requirement-conflict
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-08-29
last_seen: 2026-08-29
links:
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r1.md
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r4.md
---
# 同一份 delta 內兩條 requirement 對同一輸入互相牴觸

delta 內 ADDED 與 MODIFIED requirement 若涉及同一輸入或同一類失敗，必須對該輸入的可觀察結果給出一致的規則；一條宣稱使用者看到分類的固定指引、另一條仍以無條件規則要求顯示該階段資訊，會讓 archive 後的 master spec 自相矛盾。替某一類失敗開的例外，必須涵蓋所有同性質的分類。

## Occurrences

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — `cash-propose` Round 1：ADDED requirement 的 Example 宣稱使用者看到例外摘要，但 MODIFIED requirement 與實作都把該輸入分類為裝置鎖定、顯示固定解鎖指引。
- 2026-08-29 — `fix-device-locked-and-favorites-layout` — `cash-propose` Round 4：ADDED requirement 替鎖定與授權兩類都宣告顯示固定指引，MODIFIED requirement 的例外卻只逐字列舉鎖定。
