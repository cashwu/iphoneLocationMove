## Context

`LocationMapView` 目前讓 `preview` 同時代表 marker render state 與 preview camera intent。`LocationMapCanvas.Coordinator.update` 只要看到新的 preview coordinate，就透過 `LocationMapCameraEffects.applyPreview` 呼叫 `centerMap(on:)`；該方法固定建立 1,500 公尺 region。因此地圖直接點擊雖然語意上只是選點，也會在 SwiftUI 更新後取得 programmatic camera ownership，覆寫使用者點擊前的 visible region。

搜尋結果選取仍需要 programmatic preview center；直接地圖點擊則不需要，因為被點擊座標已在目前視野內。修正應把 marker render state 與 camera intent 分離，同時保留既有 camera effect 去重機制。

## Goals / Non-Goals

### Goals

- 直接地圖點擊更新 preview marker、地址與座標時，完整保留點擊前的 visible region，不執行平移、置中或縮放。
- 搜尋結果選取仍執行既有 preview center。
- route fit、Mac 初始置中、「到 Mac 位置」與 Reset camera intent 保持既有行為與一次性去重。
- reverse geocode 或其他 annotation redraw 不得把直接點擊的 preview 轉成 programmatic camera effect。
- 以既有 `CameraOperationSpyMapView` 直接驗證 canvas／camera effect boundary。

### Non-Goals

- 不跨 App 重啟、視窗重建，或 `simulationStore` 由 `nil` 變為非 `nil` 造成 map canvas 變體切換、`MKMapView` 與 `LocationMapCameraEffects` 一併重建時，持久化 camera region。
- 不修改 MapKit 搜尋、reverse geocode、A/B、route 或 simulation domain model。
- 不新增 camera state machine、generation type、儲存層或設定介面。

## Decisions

### 1. 由 `LocationMapModel` 分離 preview render state 與 camera intent

新增 `MapPreviewCameraIntent`，包含 `coordinate: MapCoordinate` 與既有 `MapSearchGeneration` identity；`LocationMapModel` 以 read-only published `previewCameraIntent` 持有 optional intent。`model.preview` 繼續作為 marker、地址與座標的唯一 render truth。

- `selectSearchResult(_:from:)` 成功推進 search ownership 後，以新的 `mapSearchGeneration` 與搜尋結果 coordinate 建立 intent。
- `selectMapCoordinate(_:)` 成功後把 intent 清為 `nil`。
- `beginSearch(query:)`、`clearSearch()` 與 `resetWorkspace()` 清空 preview 時一併清除 intent。
- reverse geocode 只更新 `model.preview` 的地址，不改變 intent。
- 所有 validation failure 在 mutation 前返回，MUST 保留既有 intent。

`LocationMapModel` 已持有 `routeCameraIdentity`、`macInitialCenterIntent` 與 `macRecenterIntent`，因此同一 owner 持有 preview camera intent 可讓搜尋、直接選點、搜尋開始、clear 與 Reset 的 state transition 直接由 model tests 驗證。identity 沿用既有 `MapSearchGeneration`，不新增另一套 generation。

### 2. Canvas 只以明確 intent 套用 preview camera effect

`LocationMapCanvas`、`ObservedSimulationMapCanvas` 與 `Coordinator.update` 接收 optional `previewCameraIntent`。Coordinator 仍同步 `preview` annotation，但只有 intent 非 `nil` 時才呼叫 `LocationMapCameraEffects.applyPreview` 與 `centerMap(on:)`。

`LocationMapCameraEffects.applyPreview` 改以 intent 的 `MapSearchGeneration` 去重，不再以 coordinate 去重。同一 intent 的 annotation redraw 不會重播 camera；新的搜尋 selection 即使回到相同 coordinate，也因 identity 不同而重新置中。直接點擊 intent 為 `nil`，所以第一次 render、reverse-geocode 地址更新及後續 redraw 均不會觸發 camera operation。

### 3. 新 route fit 優先，已消耗 route 不遮蔽新的搜尋 intent

`LocationMapCameraEffects.applyRoute` 回傳本次是否實際套用新的 route identity。`Coordinator.update` 先嘗試新的 route fit；若本次已套用 route，route 取得優先權，並以 `consumePreview(_:)` 消耗同輪存在的 preview identity但不執行 preview camera mutation，避免下一次 redraw 延遲重播。若 route overlay 存在但 identity 已消耗，之後才產生的新 `previewCameraIntent` SHALL 接著置中搜尋結果，不得被單純存在的 overlay 遮蔽。Mac initial center 的 eligibility gate 仍為 `preview == nil`（render state，不是 `previewCameraIntent == nil`），且仍留在 route／preview 之後的同一條 else-if chain 內：route fit 或 preview center 於本輪取得 ownership 時 MUST NOT 再評估 Mac initial center。獨立的 Mac recenter handling維持不變。

### 4. 不以 camera restore 修正

不先讓 `setRegion` 執行再還原舊 region。這會產生兩次 camera mutation與額外 delegate callback，增加 `regionWillChange` 將程式化變更誤判為手動操作的風險。直接不發出 camera operation 才能精確保留 visible region。

## Implementation Contract

1. `MapPreviewCameraIntent` SHALL 包含 `coordinate: MapCoordinate` 與 `identity: MapSearchGeneration`；`LocationMapModel.previewCameraIntent` SHALL 對 view read-only。
2. `LocationMapModel.selectSearchResult(_:from:)` 只有在 validation 與 ownership advance 成功後 SHALL 建立新的 intent；任何 failure MUST 保留既有 intent。
3. `LocationMapModel.selectMapCoordinate(_:)` 只有在 validation 與 ownership advance 成功後 SHALL 清除 intent；任何 failure MUST 保留既有 intent。
4. `LocationMapModel.beginSearch(query:)`、`clearSearch()` 與 `resetWorkspace()` 在清空 preview 時 SHALL 同步清空 intent；`receivePreviewAddress` MUST NOT 建立或改變 intent。
5. `LocationMapView` SHALL 將 `model.previewCameraIntent` 傳入兩個 map canvas 變體；不得以 view-local duplicate state 表達同一 intent。
6. `LocationMapCanvas.Coordinator.update` SHALL 始終依 `preview` 同步 annotation；只有 `previewCameraIntent != nil` 時 MAY 呼叫 `LocationMapCameraEffects.applyPreview`。
7. 直接地圖點擊產生的 preview render，以及其後的 reverse-geocode address render，MUST NOT 呼叫 `MKMapView.setRegion`、`setCenter` 或 `setVisibleMapRect`。點擊後被判定為 stale 而忽略的舊 search response 或 address response 同樣 MUST NOT 產生任何 camera operation，也 MUST NOT 建立 preview camera intent。
8. `LocationMapCameraEffects.applyPreview` SHALL 以 `MapSearchGeneration` 去重；相同 identity 重播為零次，新的 identity 即使 coordinate 相同仍 SHALL 套用一次。
9. `LocationMapCameraEffects.consumePreview(_:)` SHALL 將指定 `MapSearchGeneration` 記為已消耗但 MUST NOT 執行 camera mutation。
10. 新 route identity 與 preview intent 同時出現時 SHALL 先套用 route fit，並消耗同輪 preview identity，使後續 redraw MUST NOT 延遲執行該 preview center；route identity 已消耗後才出現的新 preview intent SHALL 置中搜尋結果。Mac initial center 與 Mac recenter 的既有 eligibility、identity 與處理順序 MUST NOT 改變：Mac initial center 的 gate SHALL 維持 `preview == nil`，且僅在本輪未套用 route fit 也未套用 preview center 時 MAY 被評估。
11. simulation state、device mutation contract 與既有 `MapSearchGeneration` 單調 ownership規則 MUST NOT 改變。
12. `iPhoneLocationMoveTests/LocationMapModelTests.swift` SHALL 驗證 model intent transitions：搜尋成功建立 intent、直接選點成功清除 intent、`beginSearch`／`clearSearch`／Reset 清除 intent、reverse geocode 保留 intent、validation failure 保留既有 intent。
13. `iPhoneLocationMoveTests/LocationMapModelTests.swift` SHALL 以擴充後的 `CameraOperationSpyMapView` 驗證 `setRegion`、`setCenter` 與 `setVisibleMapRect`：manual map-click intent 為 `nil` 時三種 camera operation counts 與 visible region 不變，包含點擊後晚到的 stale search response 被忽略的情況；programmatic search intent 置中一次；「搜尋 A → 點擊 B → 再搜尋 A」的第二次搜尋仍置中；新 route 與 preview 同輪時只 route fit且下一次 redraw不延遲重播 preview；route identity 已消耗後才產生的新搜尋仍置中；annotation/address redraw 不重播 camera。

## Risks / Trade-offs

- `previewCameraIntent` 增加一個 model-published UI intent；風險是 preview mutation path 漏同步。以 model transition tests逐一覆蓋 `selectSearchResult`、`selectMapCoordinate`、`beginSearch`、`clearSearch`、`receivePreviewAddress` 與 Reset。
- `applyRoute` 新增「本次是否套用」回傳值並搭配 `consumePreview(_:)` 判斷 precedence；既有 callers 必須同步更新，並以 route-new 同輪消耗／redraw零重播／route-consumed 後新搜尋三種 boundary tests固定行為。
- 直接點擊不會自動把 marker移到中央；這是預期行為，因為 marker 已位於使用者點擊的可見座標，且保留完整視野優先於自動置中。
