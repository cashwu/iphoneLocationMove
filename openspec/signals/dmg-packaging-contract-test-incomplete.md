---
id: dmg-packaging-contract-test-incomplete
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-package-app-script/reviews/apply-r1.md
---
# DMG contract test 未驗證 staging 內容與 replacement boundary

DMG orchestration test 必須檢查 staging 內的 App 與 `/Applications` symlink，並以相鄰 sentinel 證明只替換精確目標；只確認輸出檔存在無法防止內容缺失或過度刪除。

## Occurrences

- 2026-07-27 — `add-package-app-script` — `cash-apply` Round 1：初版 `hdiutil` shim 忽略 `-srcfolder`，也沒有保護相鄰 DMG。
