---
id: design-delivery-path-misses-member-file
type: recurring-finding
status: open
occurrences: 1
first_seen: 2026-09-05
last_seen: 2026-09-05
links:
  - openspec/changes/auto-reconnect-after-usb-replug/reviews/propose-r4.md
---
# Design 指定的成員實際定義在未列入 Impact 的檔案

design 要修改某型別的成員（例如 protocol conformance extension 的屬性或方法）時，必須 grep 該成員的實際定義位置，而不是假設它在型別主檔中；若成員定義在另一檔的 extension，且 design 又要求它讀取主檔的 `private` 狀態，proposal Impact 與 tasks delivery 都必須列入該檔並說明搬移或可見性調整，否則 apply 階段會遇到 Impact、tasks 與程式碼位置三者不符。

## Occurrences

- 2026-09-05 — `auto-reconnect-after-usb-replug` — `cash-propose` Round 4：`hasActiveSimulation`／`stopForQuit` 定義在 `AppLifecycleCoordinator.swift` 的 `extension SimulationStore`，design 卻歸給 `SimulationStore.swift` 並要求讀取 `private var userActionTask`，Impact 與 tasks 未列該檔。
