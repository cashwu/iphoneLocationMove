---
id: build-version-setting-no-metadata-consumer
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/add-package-app-script/reviews/propose-r1.md
---
# Build version setting 沒有產物 metadata consumer

打包流程宣稱以 build setting 覆寫版本時，實際產物的版本 metadata 必須引用該 setting，並在 build 後直接驗證；只把值傳給 build command 或用於檔名，不能證明交付 binary 的版本已更新。

## Occurrences

- 2026-07-27 — `add-package-app-script` — `cash-propose` Round 1：`MARKETING_VERSION` 最初沒有 `CFBundleShortVersionString` consumer，版本只反映在 DMG 檔名。
