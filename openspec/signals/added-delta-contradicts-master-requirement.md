---
id: added-delta-contradicts-master-requirement
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-mac-recenter-and-workspace-reset/reviews/propose-r1.md
---
# ADDED delta 行為與既有 master requirement 衝突

新 delta 引入的行為若落在既有 master requirement 的管轄範圍（例如解除該 requirement 的禁止條款），必須以 MODIFIED requirement 逐字承接並明文授權例外，不能只寫 ADDED requirement；否則 archive 後兩份 master 條文互相矛盾。

## Occurrences

- 2026-07-27 — `add-mac-recenter-and-workspace-reset` — `cash-propose` Round 1：工作區重置的「重新武裝初始置中」與 master「初始置中不得覆寫使用者地圖脈絡」的「不得重新取得 camera ownership」衝突，delta 最初未 MODIFIED 該 requirement。
