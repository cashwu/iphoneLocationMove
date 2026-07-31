## Context

`LocationMapView` 目前以 view-local `searchRequest` 對搜尋結果列做第一次選取前的 guard；`LocationMapModel.selectSearchResult(_:from:)` 同時要求該 request 仍是 `activeSearchRequest`。第一次選取會遞增 `MapSearchGeneration`、清除 request ownership 並建立 preview camera intent，但不會清除 `searchResults`，因此畫面仍呈現可點擊的結果列，後續點擊卻在 view guard 或 model guard 被拒絕。

`MapSearchRequest` 的必要責任是判斷 async MapKit response 是否 stale；已經收進 `searchResults` 並持續顯示的列則是同步 UI state，不應再依附已完成的 request lifecycle。既有 `MapSearchGeneration` 與 `MapPreviewCameraIntent` 已能為每次 programmatic center 提供一次性 identity，不需要新增 identity type 或 state machine。

## Goals / Non-Goals

### Goals

- 目前 `searchResults` 仍顯示期間，每一列在每次點擊時都可更新 preview。
- 連續選取不同列時，preview marker、地址、座標與 camera 依序對應最後選取的列。
- 再次選取同一列時，即使座標相同，也建立新的 `MapSearchGeneration` camera intent，讓使用者手動移開 camera 後能重新置中。
- 維持 stale MapKit response、直接地圖選點、route fit precedence 與 camera effect 單次消耗的既有保護。
- 以 model 層與同一 rendered hierarchy 的 view 層 regression tests 覆蓋原始失效路徑。

### Non-Goals

- 不改變搜尋供應者、結果排序、結果數量或 query lifecycle。
- 不新增搜尋結果 annotations 或多 marker 選取狀態。
- 不變更 iPhone mutation、A／B 指定、route、Mac recenter 或直接地圖選點 contract。
- 不拆分新 module、IPC、storage abstraction 或跨層 adapter。

## Decisions

### 1. 以目前 `searchResults` membership 作為同步選取邊界

將 model 入口收斂為 `selectSearchResult(_:)`。入口只接受仍存在於目前 `searchResults` 的 `MapSearchPlace`；不再要求呼叫者提供原始 `MapSearchRequest`。這讓可見清單就是可選候選集合，同時保留 `receiveSearchResults(_:for:)` 以 `activeSearchRequest` 與 generation 拒絕 stale async response。

沒有另建 selection identity：既有陣列已是唯一 UI truth，新增第二份 ownership 只會增加同步成本。若刪除這個 model membership gate，非目前清單的 stale place 便可能被接受，因此該邊界具有實際行為，不是 pass-through。

### 2. 每次有效選取都沿用既有 generation 建立新 camera intent

`selectSearchResult(_:)` 每次成功都呼叫既有 `advanceSearchOwnership()`，再以新的 `mapSearchGeneration` 建立 `MapPreviewCameraIntent`。即使再次選取同一座標，identity 仍不同；`LocationMapCameraEffects.applyPreview` 繼續負責單次消耗與 redraw 去重。

選取成功後清除 `activeSearchRequest`，避免已完成 query 的 response 再取得 ownership，但保留 `searchResults`，直到新搜尋、直接地圖選點、清除搜尋或 workspace reset 依既有流程清空它。

### 3. View action 不再依賴 view-local request

`LocationMapView.selectSearchResult(_:)` 直接呼叫 model 的同步選取入口，不以 `guard let searchRequest` 決定結果列是否可用。view 仍可在選取後將 `searchRequest` 清為 `nil`，因為它只代表 async query lifecycle，不代表目前清單的 selection lifecycle。

side-effect ordering 固定為先呼叫 model，再取消 view-local async work：只有 `selectSearchResult(_:)` 通過目前 `searchResults` membership 並成功更新 ownership 後，view 才可呼叫 `cancelSearch()`、`cancelPreviewAddressLookup()` 與清除 `searchRequest`。若重繪前殘留的舊結果 action 被觸發，model SHALL 先丟出 `staleSearchSelection`，view SHALL 只呈現該錯誤，MUST NOT 取消屬於較新 ownership 的 MapKit search 或 reverse-geocode。

### 4. Regression test 直接操作同一 rendered hierarchy 的結果 action

Model tests 驗證 membership gate、不同列連續選取、同列重複選取與每次 generation 前進。View test 預先配置 model 的搜尋結果，在同一個 `NSHostingView<LocationMapView>` 依序觸發兩個結果列的實際 action，驗證 preview 與 map annotation 更新。

若 SwiftUI production button 無法由目前 AppKit hierarchy 穩定取得，沿用既有 DEBUG-only `TestingActionMarker`，為每個結果列提供不與 production identifier 共用的唯一 action marker。marker MUST 維持零尺寸、不可 hit-test、非 accessibility element 且拒絕 first responder，action 必須呼叫與可見結果列相同的 `selectSearchResult(_:)`，不得建立另一套選取邏輯。

由於 `MKLocalSearch` 與 `CLGeocoder` concrete instances 沒有現成可控制的 spy 邊界，view regression tests MAY 透過 DEBUG-only `onSearchCancellationRequested` 與 `onPreviewAddressCancellationRequested` observers，直接觀察既有 production cancellation functions 是否被要求執行。observer 名稱 SHALL 表明它只證明 cancellation path 被要求，不宣稱當下必然存在可取消的 concrete operation；Release build MUST NOT 包含這兩個 test-only initializer parameters 或 stored closures。

## Implementation Contract

1. `LocationMapModel.selectSearchResult(_:)` SHALL 驗證傳入 place 存在於目前 `searchResults`；不在集合內時 SHALL 丟出既有 `LocationMapError.staleSearchSelection`，且不得改變 preview、generation 或 camera intent。
2. 每次成功選取 SHALL 遞增既有 `MapSearchGeneration`，將 `preview` 設為該 place，並建立 identity 等於新 generation 的 `MapPreviewCameraIntent`。
3. 成功選取 SHALL 將 `activeSearchRequest` 設為 `nil`，但 MUST NOT 清空或替換 `searchResults`。
4. 連續選取不同結果與重複選取同一結果 SHALL 走完全相同的 model path；不得以 coordinate equality 去重。
5. `LocationMapView` 的結果列 action SHALL 在沒有 current `searchRequest` 時仍先呼叫 `selectSearchResult(_:)`；只有 model 成功後才能取消 view-local search／preview-address lookup 並清除 `searchRequest`。model 拒絕 stale selection 時，錯誤仍使用既有 `show(_:)` 呈現，且 MUST NOT 取消任何較新的 async operation。
6. 新搜尋、直接地圖選點、清除搜尋與 workspace reset SHALL 保持既有清單失效規則；舊 MapKit response 仍由 `receiveSearchResults(_:for:)` 的 request/generation gate 拒絕。重繪前殘留的舊結果 action MUST NOT 取得 ownership 或取消較新 request。
7. `LocationMapCameraEffects` 的 route precedence 與一次性 preview consumption MUST NOT 改變；annotation／overlay redraw MUST NOT 重播已消耗 intent。
8. View regression test SHALL 在同一 rendered hierarchy 依序觸發至少兩個仍顯示的搜尋結果 action，並觀察同一 map view 的 preview annotation 從第一個座標移至第二個座標。
9. View regression test SHALL 另驗證再次觸發同一結果會產生新的 camera operation；測試 MUST NOT 只直接呼叫 model 而略過 view action。
10. Owner/view boundary regression test SHALL 建立較新的 search ownership，再觸發重繪前殘留的舊結果 action，驗證 model state 不變且較新的 search／preview-address async operation未被取消。
11. Owner/view boundary regression test SHALL 斷言 stale selection 仍顯示既有錯誤區域；測試使用的 cancellation-request observers MUST 僅存在於 DEBUG build，成功路徑 SHALL 作為 positive control 證明 observers 已接到相同 cancellation functions。

## Risks / Trade-offs

- `searchResults` 從 request lifecycle 解耦後會比 `activeSearchRequest` 存活更久；風險由 membership gate 與既有清空路徑限制，且符合畫面仍顯示清單的使用者期待。
- 每次重複點同一列都會執行 programmatic center；這是刻意行為，讓手動移開 camera 後可回到結果。代價是一個重複點擊也會觸發動畫，但比無反應更一致。
- DEBUG action marker 與 cancellation-request observers 增加少量測試 seam；它們必須沿用既有不可見、不可 focus、不可 accessibility 的限制或完全排除於 Release build，並以獨立 identifier 避免與 production control identity 碰撞。
- 先 model validation、後 view-local cancellation 讓 stale action 不再具有取消副作用；代價是成功選取到實際 cancel 之間存在極短同步區段，但兩步都在 `@MainActor` 執行，不會被另一個 UI action 插入。
