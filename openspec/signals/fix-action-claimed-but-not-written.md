---
id: fix-action-claimed-but-not-written
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-08-29
last_seen: 2026-08-29
links:
  - openspec/changes/fix-device-locked-and-favorites-layout/reviews/propose-r2.md
---
# Fix Action 宣稱已修但檔案未變更

以指令碼批次套用 artifact 編輯時，若把多筆替換累積在記憶體中、最後才一次寫檔，任何一筆中途失敗都會連同已成功的替換一起丟棄，而 round file 的 Fix Actions 卻已記為完成。批次編輯應逐筆讀寫，並在套用後以 grep 驗證舊字串殘留為 0、新字串存在，才寫入 Fix Actions。

## Occurrences

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — `cash-propose` Round 2：Round 1 宣稱改寫的 `tasks.md` task 1.1、1.2 與 1.5 三筆編輯完全未寫入，指令碼在第四筆斷言失敗而中止於寫檔之前。
