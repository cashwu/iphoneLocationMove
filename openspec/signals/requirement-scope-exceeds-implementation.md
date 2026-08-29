---
id: requirement-scope-exceeds-implementation
type: recurring-finding
status: open
occurrences: 2
first_seen: 2026-08-29
last_seen: 2026-08-29
links:
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r1.md
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r3.md
---
# Requirement 宣告的涵蓋範圍超過實作

requirement 列舉階段、輸入來源或條件時，必須逐一對照實作的實際覆蓋路徑。宣稱涵蓋七個 prerequisite 階段但分類只掛在其中四個走同一子行程入口的階段、宣稱檢視整個輸出串流但實作只檢視收斂後的單一摘要行，都會讓 archive 後的 master spec 對未實作的行為做出承諾。

## Occurrences

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — `cash-propose` Round 1：MODIFIED requirement 宣稱鎖定分類涵蓋七個階段，但 tunnel 與 DVT 走 privileged helper 與 helper 程序而不做鎖定判定。
- 2026-08-29 — Round 3：spec 宣稱分類同時檢視兩個串流，實作只檢視各串流雜訊過濾後的單一摘要行。
