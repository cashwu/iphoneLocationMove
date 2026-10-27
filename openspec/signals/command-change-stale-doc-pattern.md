---
id: command-change-stale-doc-pattern
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-10-27
last_seen: 2026-10-27
links:
  - openspec/changes/fix-ios-27-2-classic-tunnel/reviews/propose-r1.md
---
# 改變固定 command 後，文件中的 process 比對字串未同步

變更 helper 或子程序的固定 command／arguments 時，必須 grep 整個 repo（含 acceptance 手冊、runner、README）中比對舊 command 的 `pgrep`／regex／字串，並把這些檔案列入 proposal Impact 與 tasks delivery；否則清理或殘留檢查可能過期而產生假陰性。

## Occurrences

- 2026-10-27 — `fix-ios-27-2-classic-tunnel` — `cash-propose` Round 1：helper 由 `remote start-tunnel --native` 改為 `lockdown start-tunnel`，但 `iPhoneLocationMoveTunnelHelper/Acceptance/PRODUCTION_ACCEPTANCE.md` 的 `pgrep` pattern 仍為 `pymobiledevice3.*remote.*tunnel`，且未列入 Impact。
