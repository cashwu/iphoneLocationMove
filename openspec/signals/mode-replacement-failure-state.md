---
id: mode-replacement-failure-state
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-26
last_seen: 2026-07-26
links:
  - openspec/changes/add-macos-location-simulator/reviews/propose-r1.md
---
# Mode replacement 第一個 mutation 失敗時狀態未定義

停止舊 producer 後，新模式第一個外部 mutation 可能失敗；此時不能宣稱 idle 或新模式 active，必須保留 cleanup ownership 與不確定狀態。

## Occurrences

- 2026-07-26 — `add-macos-location-simulator` — `cash-propose` Round 1：point／route replacement 最初只定義成功路徑。
