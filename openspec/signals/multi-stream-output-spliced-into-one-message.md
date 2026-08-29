---
id: multi-stream-output-spliced-into-one-message
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-08-29
last_seen: 2026-08-29
links:
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r1.md
---
# 多個輸出串流被接合成單一訊息

把 standard error 與 standard output 串接後再做結構切割與接合，會讓兩個獨立串流的內容被拼成一個看似完整的假句子。每個串流應各自摘要；顯示用細節只取單一串流，另一串流僅在前者無可用內容時作為來源。分類若需涵蓋兩個串流，應對各自的摘要分別判定而非接合後判定。

## Occurrences

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — `cash-propose` Round 1：`summarize` 把 stderr 與 stdout 串接後取方框邊界之後的所有行接合，使 stdout 內容被接到例外摘要之後。
