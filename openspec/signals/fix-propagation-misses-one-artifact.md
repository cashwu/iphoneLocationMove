---
id: fix-propagation-misses-one-artifact
type: recurring-finding
status: open
occurrences: 3
first_seen: 2026-08-29
last_seen: 2026-09-05
links:
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r3.md
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r4.md
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r5.md
  - openspec/changes/auto-reconnect-after-usb-replug/reviews/propose-r2.md
---
# 修復只傳播到部分 artifact

跨 artifact 的行為敘述修改後，必須把該概念在 proposal、design Decisions、design Implementation Contract、tasks 敘述與 success、spec requirement 與 scenario、程式碼與測試逐一同步；其中 proposal 最常被遺漏。殘留掃描的 pattern 必須短且不含可變修飾語——以完整句子為 pattern 時，措辭的細微差異會讓掃描回報 0 而漏抓。

## Occurrences

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — `cash-propose` Round 3：分類同時檢視兩個串流的修改漏掉 `proposal.md`。
- 2026-08-29 — Round 4：改為串流優先序後 design Decisions、tasks 1.5 與 spec MODIFIED 三處仍保留舊的全域宣稱。
- 2026-08-29 — Round 5：改回標記優先後 `proposal.md` 再次成為唯一漏掉的 artifact；殘留掃描用完整句子當 pattern 而漏抓。
- 2026-09-05 — `auto-reconnect-after-usb-replug` — `cash-propose` Round 2：round 1 把 `reconnecting` 改為不持有 cleanup ownership時同步了 design、spec、tasks，漏掉 proposal.md Proposed Solution 一處。
