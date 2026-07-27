## Context

`LocationMapView.controls` 是固定 320 pt 寬的 `ScrollView`，內容由根 `VStack(alignment: .leading, spacing: 16)` 串接多個局部 `VStack`／`HStack`。目前各 `Button` 依標題與容器自行決定 intrinsic size；新加入的「到 Mac 位置」與 `Reset` 又是根層 sibling，沒有共同的寬度與群組規則。DEBUG hosting-view seam 使用 `TestingActionMarker: NSViewRepresentable` 回傳 `NSButton`，並放在 production control 的 `.background`；AppKit view 可能取得非零 frame 或 focus ring，造成截圖中的重疊文字／外框，即使 action 尚未執行也會出現。

本 change 僅修正地圖控制欄的布局與測試 seam 呈現。按鈕 action、disabled 條件、role、confirmation、state ownership 與地圖／模擬行為維持不變。

## Goals / Non-Goals

**Goals**

- 讓側欄所有可見按鈕在固定 320 pt 欄寬內有一致、可預期的水平對齊與群組間距。
- 讓按鈕在 connected／disconnected、busy、route action 與 clear failure 等條件式內容切換時保持不重疊、不越界。
- 讓 DEBUG `TestingActionMarker` 保留既有測試 action 與 accessibility identifier，但不可見且不參與 SwiftUI 布局。
- 以 hosting-view regression test 驗證同一 rendered hierarchy 的實際 frame，而不只驗證 state property。

**Non-Goals**

- 不改變側欄 320 pt 寬度、地圖尺寸、字體、色彩或按鈕文案。
- 不改變任何定位、路線、搜尋、Reset 或確認流程。
- 不建立跨 App design system、自訂控制元件階層或第三方 snapshot dependency。
- 不將所有按鈕強制設成相同寬度；同列按鈕保留符合內容的寬度，重點是共同 baseline、間距與邊界。

## Decisions

1. **使用一個 file-private、無狀態的 layout modifier 統一單列操作。** 在 `LocationMapView.swift` 內新增小型 `View` extension（命名 `mapSidebarPrimaryActionLayout()`），只套用 `.frame(maxWidth: .infinity, alignment: .leading)`。單獨成列的「到 Mac 位置」、`Reset`、「建立步行路線」、「設定位置」、「開始步行路線」與「停止模擬」套用此 modifier；它不改 label、role、disabled 或 action。
2. **同列按鈕由明確的 row 容器管理。** 搜尋／清除、設為 A／B、暫停／繼續等既有同列操作維持 `HStack`，統一使用 `spacing: 8` 與 `.frame(maxWidth: .infinity, alignment: .leading)`。不以 `Spacer` 拉開按鈕，避免短標題在欄內漂移到兩端。
3. **新 top-level 操作形成獨立群組。** 「到 Mac 位置」與 `resetControl` 放入 `VStack(alignment: .leading, spacing: 8)`，群組本身填滿側欄可用寬度。根層 `VStack` 的 16 pt spacing 繼續分隔搜尋、預覽、路線、模擬狀態等功能群組，避免兩顆新增按鈕各自消耗一個根層 section gap。
4. **測試 marker 使用可辨識且不可 focus 的專用 AppKit control。** 新增 internal `TestingActionButton: NSButton`，覆寫 `intrinsicContentSize` 為 `.zero`、`acceptsFirstResponder` 為 `false`，並設定 `refusesFirstResponder = true`。`TestingActionMarker` 繼續回傳可由測試尋找並 `performClick` 的此 subclass，但設定空標題、無 border、無 focus ring、透明、非 accessibility element，且每個 SwiftUI 使用點以固定零尺寸 frame 放置並禁止 hit testing。production 與 marker 可保留相同 accessibility identifier；測試一律依具體型別區分，production 可見控制仍是唯一承接使用者點擊與 focus 的元素。marker action 不變，因此 Reset 測試仍先觸發 production confirmation entry，再觸發 DEBUG confirmation seam。
5. **hosting-view 直接驗證 production control 與狀態區域 frame。** 在既有 `ContentViewTests.swift` 共用 hosting helper 中，以側欄座標系收集可見 production `NSButton`，依 `TestingActionButton` 型別排除 marker，且不以共享 identifier 篩選 production control。新增 DEBUG-only `TestingLayoutRegionView: NSView` 與對應 `NSViewRepresentable`，讓速度、模擬狀態、錯誤與裝置就緒文字各以 background probe 標記實際區域；probe 的 `intrinsicContentSize` 為 `.zero`，只回報父 view 提議的 frame，不繪製、不接受 focus 或 hit testing。測試依 `TestingLayoutRegionView` 型別收集，不依 SwiftUI 私有 view hierarchy。測試 oracle 為：每個可見按鈕 frame 的 `minX`／`maxX` 位於側欄 content bounds、任兩個不同 row 的 frame 不相交、同一 row 的 frame 不重疊且至少相距 8 pt、每個按鈕與每個可見狀態區域 frame 不相交（允許 1 pt rendering tolerance）；單列主要操作的 `minX` 一致。另直接收集 `TestingActionButton` 並斷言 frame width／height 為 0、透明、無 focus ring、`acceptsFirstResponder == false`、`refusesFirstResponder == true` 且非 accessibility element。
6. **在同一 rendered hierarchy 驗證 observation 與條件式布局。** disconnected 初始化分支使用獨立 fixture；connected fixture 則只建立一次 `NSHostingView<LocationMapView>`，先驗證 idle，再驅動同一個 observed `SimulationStore` 進入 busy、route running、route paused 與 stopping failure，每次等待既有 hierarchy invalidation／layout 後重跑完整 production button、狀態區域與 marker oracle。route paused 驗證必須以有 timeout 的條件同時等待 model phase 與 `sidebar-button-resume-route` layout region materialize，不得只等待 model state。原本的 Reset confirmation、disabled 與 clear failure 行為測試保持不變，作為本次不得改變行為的 regression gate。

## Implementation Contract

- `iPhoneLocationMove/Features/Map/LocationMapView.swift`
  - 新增 file-private `mapSidebarPrimaryActionLayout()`，內容僅為填滿可用寬度並靠左對齊，不加入 style、padding、minimum size 或 action 邏輯。
  - `controls` 將「到 Mac 位置」與 `resetControl` 包在 `VStack(alignment: .leading, spacing: 8)`，並讓群組 frame 填滿可用寬度、靠左。
  - 所有單獨成列的側欄按鈕套用 `mapSidebarPrimaryActionLayout()`，包含 transient route failure 的「重試」；動態搜尋結果按鈕維持既有的 full-width plain row。所有多按鈕 row 明列 `HStack(spacing: 8)` 且填滿可用寬度、靠左。
  - 新增 DEBUG-only `TestingActionButton: NSButton`；`intrinsicContentSize == .zero`、`acceptsFirstResponder == false`、`refusesFirstResponder == true`。`TestingActionMarker.makeNSView` 建立此型別並設定空標題、`isBordered = false`、`focusRingType = .none`、不透明度為 0、非 accessibility element；marker 使用點固定為零尺寸且 `.allowsHitTesting(false)`。`identifier`、`isEnabled`、`isOn` 與 `action` 更新語義維持不變。
  - 新增 DEBUG-only `TestingLayoutRegionView: NSView` 與對應 `NSViewRepresentable`，並為速度、模擬狀態、錯誤與裝置就緒文字加上 layout probe background；probe 必須無 intrinsic size、不可 focus、不可 hit test、無繪製且非 accessibility element，不得改變 production layout 或 accessibility。
  - 不改變任何 Button action、role、disabled expression、accessibility identifier、confirmation dialog 或 state mutation ordering。
- `iPhoneLocationMoveTests/ContentViewTests.swift`
  - 新增 frame 轉換、production button、`TestingActionButton` 與 `TestingLayoutRegionView` 收集 helper，以 `NSView.convert(_:to:)` 將 frame 轉至 hosting root 或 sidebar coordinate space；共享 identifier 不得作為 marker／production 分類依據。
  - 新增 disconnected 初始化測試，並在同一個 connected hosting hierarchy 依序驗證 idle、busy、route running、route paused、stopping failure；每次 observed state 更新後等待 view invalidation 與 layout，再驗證按鈕未越出 320 pt 側欄、互不重疊、不與可見狀態區域相交、row spacing 與主要操作左邊界一致。
  - 新增 marker 零尺寸、透明、無 focus ring、不可接受 first responder、拒絕 first responder 且非 accessibility element 的斷言，並保留現有 `confirmReset` 測試路徑，確保 seam 沒有繞過 production confirmation。
  - 測試使用現有 `ContentViewTests.swift` target membership，不新增測試檔或修改 `iPhoneLocationMove.xcodeproj/project.pbxproj`。

## Risks / Trade-offs

- SwiftUI 產生的 AppKit hierarchy 可能隨 macOS SDK 有細微 1 pt 差異；frame oracle採 1 pt tolerance，避免把像素 rounding 當 regression。
- 零尺寸 marker 仍是 DEBUG hierarchy 中的 AppKit node，這是保留既有 deterministic action seam 的取捨；專用 subclass 的零 intrinsic size、不可接受 first responder、透明、無 focus ring、零 frame 與禁止 hit testing共同確保使用者不可見且不攔截操作。
- `.frame(maxWidth: .infinity, alignment: .leading)` 會讓單列 Button view 佔滿 row，但 label 仍靠左且樣式不變；這會擴大部分空白區的 hit region。因使用者要求檢查所有按鈕位置，較穩定的 row ownership優先於依標題浮動的 intrinsic row；不改變相鄰控制間的視覺間距。
