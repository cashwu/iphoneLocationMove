# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

- **C1** — severity: Critical, confidence: 100, layer: design
  - location: specs/mac-map-initial-location/spec.md（重置後鏡頭行為）對照 master spec「初始置中不得覆寫使用者地圖脈絡」
  - summary: 重置後「重新武裝初始置中」與 master spec「重新連線更新位置」scenario 的「系統不得重新取得 camera ownership」直接衝突，且 delta 原本只有 ADDED、未 MODIFIED 該 requirement，archive 後兩份 master 條文互相矛盾。
  - recommendation: 於 mac-map-initial-location delta 補 MODIFIED requirement，明文授權工作區重置為唯一重新武裝路徑。
  - 來源: Reviewer A（原 confidence 75；主 agent 對照 openspec/specs/mac-map-initial-location/spec.md 逐字驗證衝突條文成立，屬直接違反 artifact 明文要求，依 rubric 提升為 100）

### Warning

- **W1** — severity: Warning, confidence: 100, layer: design
  - location: design.md Decisions 第 8 點對照 Implementation Contract 與 tasks 2.3
  - summary: Decision 8 前半稱沿用 `PendingMutation` 機制、後半與 Implementation Contract／tasks 稱由 `LocationMapView` 自有 state 驅動且不共用 `SimulationControls` 對話框 state，兩者互斥（`PendingMutation` 是 `SimulationControls` 的 private enum）。
  - recommendation: 統一為 `LocationMapView` 持有的獨立確認 state。
  - 來源: Reviewer A
- **W2** — severity: Warning, confidence: 100, layer: design
  - location: specs/location-simulation/spec.md「清空…錯誤訊息」對照 design Implementation Contract（僅清 `LocationMapView.message`）
  - summary: `SimulationControls` 另有 private `@State var message`（LocationMapView.swift:565），reset 無法清除，先前失敗訊息殘留，違反本 change spec 的「清空錯誤訊息」；與已落實一半的 `swiftui-sibling-observation-boundary` 同 issue class。
  - recommendation: 將 `SimulationControls.message` 與 `roundTrip` 同法上移以 Binding 傳入，reset 一併清空。
  - 來源: Reviewer A（confidence 70）與 Reviewer B（confidence 75）獨立提出，聚合；主 agent 驗證 LocationMapView.swift:13 與 :565 兩個 `message` state 並確認 spec 條文遭違反，提升為 100
- **W3** — severity: Warning, confidence: 100, layer: design
  - location: tasks.md 第 3 節對照 specs/location-simulation/spec.md 各 scenario 與 Example
  - summary: spec Example「往返循環關閉」與多個 scenario（警語兩分支、busy disabled、有清理責任才 stop、clear 失敗不掩蓋）無任何對應測試任務。
  - recommendation: 補 view 層測試任務（沿用 ContentViewTests hosting-view 模式）並把警語選擇抽成可測純函式。
  - 來源: Reviewer A（confidence 100）與 Reviewer B（confidence 75）獨立提出，聚合

### Suggestion

- **S1** — confidence: 100, layer: design — task 3.2 漏 `MapPreviewAddressRequest`（`receivePreviewAddress`）的 stale 驗證，spec 明文含 reverse geocode。（Reviewer A）
- **S2** — confidence: 50, layer: design — Decision 2「優先於效果鏈」與「先檢查」語義不一致：先套用者會被同一 update 內其他新 identity 效果覆蓋。建議明定 recenter 最後套用、勝出。（Reviewer A）
- **S3** — confidence: 100, layer: text — design Context 誤稱 `applyPreview` 為 identity 模式，實為座標相等去重（LocationMapView.swift:957）。（Reviewer A）
- **S4** — confidence: 75, layer: text — spec 把警語選擇綁在「執行當下」，但警語必然於對話框顯示時呈現，與 design「顯示當下計算、stop 以執行當下判定」不一致。（Reviewer A）
- **S5** — confidence: 50, layer: text — `applyMacRecenter` gate 測試被放在 ContentViewTests，但既有全部 CameraEffects gate 測試在 LocationMapModelTests.swift:419 起。（Reviewer A；主 agent 驗證屬實）
- **S6** — confidence: 50, layer: design — reset 執行順序漏清 view 的 `searchRequest` `@State`，「等同 App 剛啟動」不完整。（Reviewer A 與 Reviewer B 獨立提出，聚合）
- **S7** — confidence: 50, layer: design — `macRecenterIntent` 無消耗機制，`LocationMapCanvas` 重新 `makeCoordinator` 時去重狀態歸零可重播置中（對應 `view-lifecycle-request-deduplication`）。原 Reviewer B Warning，confidence 50 依 filter 降為 Suggestion。（Reviewer B）

### 濾除（confidence < 50）

- Reviewer B Finding 5（confidence 25）：proposal 未宣告對 in-progress change `add-macos-location-simulator` 的順序依賴。依 confidence filter 濾除；downgrade trace 記於 Fix Actions。

## Rating

- post-filter cumulative blocking set：Critical 1（C1）、Warning 3（W1、W2、W3）
- non-blocking triaged findings：7（S1–S7）
- critical_gap: true
- round_type: full
- 理由：本輪為 run 首輪，全部 surviving Critical／Warning 皆為 blocking。C1 經主 agent 對照 master spec 驗證為直接條文衝突，W1–W3 均為 artifact 間可驗證的不一致或驗收缺口，blocking set 非空，故 decision 為 next_round。

## Fix Actions

confidence 調整與 downgrade traces：

- C1：Reviewer A 原報 75，主 agent 驗證 master spec 條文後提升為 100（直接違反 artifact 明文要求）。
- W2：Reviewer A 70／Reviewer B 75，主 agent 驗證程式碼與 spec 條文後提升為 100。
- S7：Reviewer B 原報 Warning confidence 50，依 confidence filter [50, 80) 降為 Suggestion。
- Reviewer B Finding 5：confidence 25，低於 50 濾除（不採取修正）。

修正（全部 blocking 與全部 suggestion 均已處理）：

- C1 → specs/mac-map-initial-location/spec.md：新增 `## MODIFIED Requirements` 段，完整重述「初始置中不得覆寫使用者地圖脈絡」requirement（標題自 master byte-for-byte 複製），敘述句新增「工作區重置 SHALL 為唯一重新武裝初始置中的操作」，「重新連線更新位置」scenario 增加「其後未發生工作區重置」條件，並新增「工作區重置後重新武裝初始置中」scenario；proposal.md Modified Capabilities 同步敘明。
- W1 → design.md Decision 8：刪除「沿用 `PendingMutation` 機制」句，統一為 `LocationMapView` 持有的獨立確認 state；同步 tasks 2.3。
- W2 → design.md Decision 7、Context、Implementation Contract、Risks 與 tasks 2.3：`roundTrip` 與 `SimulationControls.message` 皆上移、各以 Binding 傳入，reset 清空兩個訊息 binding。
- W3 → design.md 測試段與 tasks：新增 tasks 3.4（ContentViewTests hosting-view 模式：roundTrip／搜尋框清空、busy disabled、有清理責任才 stop、clear 失敗不掩蓋且工作區維持重置）、警語選擇抽成純函式 `ResetConfirmationContent.make(hasCleanupOwnership:)`（design Decision 8、tasks 2.3、3.3），原 3.4 改編號為 3.5。
- S1 → tasks 3.2 與 design 測試段：補 `MapPreviewAddressRequest` stale 驗證。
- S2 → design Decision 2 與 Implementation Contract、tasks 2.1：明定 recenter 於既有鏈之後套用、同一 update 內最後套用勝出。
- S3 → design Context：改為「`applyRoute`／`applyMacCenter` 以 identity 去重、`applyPreview` 以座標相等去重」。
- S4 → specs/location-simulation/spec.md：警語條件改為「顯示確認對話框當下」；stop 判定維持「執行當下」。
- S5 → tasks 3.3 與 design 測試段：gate 測試改置於 LocationMapModelTests.swift（與既有 gate 測試同置）；ContentViewTests 留給 view 層測試。
- S6 → design Implementation Contract 與 tasks 2.3：reset 執行順序補 `searchRequest = nil`。
- S7 → design Decision 3、Implementation Contract 與 Risks：`recordUserMapContext()` 擴為同時清除未消耗的 `macRecenterIntent`，界定 intent 存活期；Risks 新增 coordinator 重建邊界條目（與既有 `macInitialCenterIntent` 同曝險，接受殘餘風險）；同步 tasks 1.1、3.1。

修正檔案清單：design.md、tasks.md、proposal.md、specs/mac-map-initial-location/spec.md、specs/location-simulation/spec.md（均在 change 目錄內，無需 touched record）。

post-fix 驗證：

- 「$cash_cli」validate add-mac-recenter-and-workspace-reset → Validation passed。
- post-fix mechanical self-check：MODIFIED requirement 標題與 master byte-for-byte 一致；註解配對 0/0；新 identifier（ResetConfirmationContent、recordManualCameraInteraction、searchRequest）在 design 與 tasks 一致；tasks 引用的 Decisions 第 2／5／8／9 點均存在。無失敗。

## Decision

next_round
