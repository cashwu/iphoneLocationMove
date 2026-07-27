---
id: recursive-isolation-oracle-incomplete
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-package-app-script/reviews/apply-r1.md
---
# Isolation test 使用淺層 directory stat 作為 oracle

宣稱隔離 fixture 未修改 repository output 時，必須比較遞迴 content manifest 或受控 sentinel；只比較頂層 directory stat 可能漏掉既有子檔被覆寫。

## Occurrences

- 2026-07-27 — `add-package-app-script` — `cash-apply` Round 1：repository build isolation 初版只比較 `build/` 本身的 mtime、ctime 與 size。
