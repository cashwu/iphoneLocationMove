---
id: artifact-claimed-coverage-exceeds-oracle
type: recurring-finding
status: open
occurrences: 5
first_seen: 2026-08-29
last_seen: 2026-08-29
links:
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r1.md
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r3.md
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r4.md
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r6.md
---
# Artifact 宣稱的測試涵蓋大於實際可證偽範圍

tasks 的 `success`／`red` 與 design 的測試清單所宣稱涵蓋的規則，必須是把該規則改壞後會有測試失敗的規則。單行 fixture 無法證偽「取最後一個」語意、不含對立標記的輸入無法證偽分類優先序、走測試專用接縫的斷言無法證偽 production 路徑、位於結構切割之外的內容無法證偽雜訊過濾規則。驗收敘述寫下之前，應以刻意破壞該規則的實驗確認至少一個案例會失敗。

## Occurrences

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — `cash-propose` Round 1：task 1.5 宣稱分類順序由既有測試涵蓋，但該路徑住在 private actor 內、既有測試全走 fake boundary。
- 2026-08-29 — Round 3：task 1.5 的 `red` 宣稱分支對調會被抓到，但無任何 fixture 同時含鎖定與授權標記。
- 2026-08-29 — Round 4：`lastMeaningfulLine` 的「取最後一個」語意零覆蓋，`.last` 改 `.first` 全套仍綠。
- 2026-08-29 — Round 6：production 端截斷走 `classify` 而唯一截斷測試走測試接縫 `summarize`；五條雜訊規則中三條因位於方框結構切割之外而零覆蓋。
