# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

無。

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `design.md` Decisions 4–5、Implementation Contract；`summary`: production Reset 與 `TestingActionMarker` 共用 `workspace-reset-button`，但原 frame oracle 依 identifier 排除 marker，會同時排除 production control 或讓 marker 斷言取錯節點；`recommendation`: 以專用 `NSButton` subclass 型別區分 marker，保留共享 identifier 並讓 production Reset 留在 frame oracle；reviewer source: Reviewer A — Adherence、Reviewer B — Quality。
2. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `design.md` Decision 6、Implementation Contract tests、`tasks.md` 2.2–2.3；`summary`: 原 artifacts 以四個獨立畫面驗證狀態，沒有在同一個已 render hosting hierarchy 內驅動 observed `SimulationStore` 更新，無法證明 SwiftUI invalidation 後仍維持布局；`recommendation`: connected fixture 只建立一次，依序切換 idle、busy、stopping failure，每次等待 view update 後重跑完整 oracle；reviewer source: Reviewer A — Adherence、Reviewer B — Quality。
3. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `design.md` Decision 5、Implementation Contract tests、`tasks.md` 2.1、2.3；`summary`: 原 frame oracle 只比較 button-vs-button，無法驗證 delta spec 的按鈕不得覆蓋速度、模擬狀態、錯誤或裝置就緒文字；`recommendation`: 為狀態文字加入 layout-neutral probe，收集其 frame 並加入 button-vs-status-region 不相交斷言；reviewer source: Reviewer A — Adherence、Reviewer B — Quality。
4. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `design.md` Decision 4、Implementation Contract marker、`tasks.md` 1.2、2.2；`summary`: 零尺寸、透明、`focusRingType = .none` 與 `.allowsHitTesting(false)` 沒有禁止底層 `NSButton` 成為 AppKit first responder；`recommendation`: 專用 marker subclass 明確拒絕 first responder，並新增 first-responder、key focus 與 accessibility 斷言；reviewer source: Reviewer A — Adherence、Reviewer B — Quality。

### Suggestion

無。

## Rating

- post-filter cumulative blocking Critical count: 0
- post-filter cumulative blocking Warning count: 4
- non-blocking triaged finding count: 0
- `critical_gap`: false
- `round_type`: full

Round 1 的四項 Warning 均有直接 artifacts 與實際程式碼證據，`confidence` 皆達 100，因此全部進入 cumulative blocking set。修正已完成，但依規則必須由下一輪 fresh reviewer 驗證後才能移除，故本輪為 `next_round`。

## Fix Actions

- 修改 `openspec/changes/fix-map-sidebar-control-layout/proposal.md`：同步補上專用 marker subclass、不可取得鍵盤 focus、狀態文字 frame 與同一 rendered hierarchy 驗證範圍。
- 修改 `openspec/changes/fix-map-sidebar-control-layout/design.md`：新增 `TestingActionButton` 的零 intrinsic size／不可 first responder contract；以具體型別區分共享 identifier 的 marker 與 production control；新增 `TestingLayoutRegionView` 狀態區域 probe；connected fixture 改為在同一 hosting hierarchy 依序驗證 idle、busy、stopping failure；補列 transient route failure「重試」與動態搜尋結果按鈕的布局分類。
- 修改 `openspec/changes/fix-map-sidebar-control-layout/specs/location-simulation/spec.md`：明定同一 rendered hierarchy 的 observed-state 切換，並要求 marker 拒絕成為 first responder。
- 修改 `openspec/changes/fix-map-sidebar-control-layout/tasks.md`：加入 `TestingActionButton`、`TestingLayoutRegionView`、button-vs-status-region frame oracle、同一 connected hierarchy 狀態轉換與 first-responder／accessibility 驗證 tasks。
- Fix propagation：跨全部 artifacts grep `TestingActionButton`、`TestingLayoutRegionView`、`TestingActionMarker`、`first responder`、`同一 rendered hierarchy` 與 `mapSidebarPrimaryActionLayout()`，確認名稱與語義一致。
- Post-fix mechanical self-check：delta annotation `<!--`／`-->` 皆為 0；無 stray `---`；1 個 requirement、4 個 scenarios 與 9 個 tasks 的相關數字敘述一致；本 change 沒有 MODIFIED／REMOVED／RENAMED title identity；所有 open signals 均無 `check` field。
- Post-fix validation：`cash validate fix-map-sidebar-control-layout` 通過。

## Decision

next_round
