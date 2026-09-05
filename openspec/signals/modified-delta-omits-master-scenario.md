---
id: modified-delta-omits-master-scenario
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-09-05
last_seen: 2026-09-05
links:
  - openspec/changes/auto-reconnect-after-usb-replug/reviews/propose-r3.md
---
# MODIFIED delta 漏抄 master 的既有 scenario

以 MODIFIED 承接 master requirement 時，archive 會用 delta 整段取代 master；若手動或以片段截取複製正文而漏掉任一 scenario、Example 或正文段落，該內容會被靜默刪除。撰寫 MODIFIED 時應以程式自 master 擷取整段（至 `@trace` 註解前）再做刻意修改，並以段落 diff 自檢確認差異只剩預期修改、scenario 數量不少於 master。

## Occurrences

- 2026-09-05 — `auto-reconnect-after-usb-replug` — `cash-propose` Round 3：新增 MODIFIED「工作區重置」時以行號區間截取 master，漏掉最後一個 scenario「重置後的鏡頭行為」。
