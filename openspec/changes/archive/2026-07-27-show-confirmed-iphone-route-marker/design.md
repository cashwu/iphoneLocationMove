## Context

`LocationMapView` 目前把 preview、A／B、route polyline 與 Mac location 傳入 `LocationMapCanvas`，但沒有傳入 `SimulationStore.routeSnapshot.confirmedCoordinate`。`SimulationControls` 雖以 `@ObservedObject` 觀察同一個 `SimulationStore`，該 observation 只會 invalidates controls subtree，不會保證 sibling map canvas 重算輸入。

`RouteSession.confirmedCoordinate` 在device mutation成功後才更新，是route當下可信位置的唯一domain truth；route state透過`RouteSimulationSnapshot.confirmedCoordinate`公開，stopping state則仍由同一route session保留。pending mutation、transport recovery與correction barrier都由現有`SimulationStore`／`RouteSession`管理，本change不需要新的progress或recovery state。

目前 `LocationMapCanvas.Coordinator.update` 每次 render 會移除全部 annotations 後重建；若把約每秒更新的 route marker直接加入此路徑，會讓所有 marker identity 與 callout 持續重置。既有 `LocationMapCameraEffects` 已以 identity gate route fit 與 Mac initial center，route marker更新不得觸發這些 effect。

## Goals / Non-Goals

### Goals

- 地圖以視覺上獨立的 marker 顯示 iPhone 已確認 route coordinate。
- marker 直接隨 `SimulationStore` publisher 更新，且只反映 confirmed state。
- marker 每秒更新時維持 annotation identity，不重建其他 annotations。
- marker lifecycle 與 route pause、complete、interruption、clear、replacement 一致。
- marker更新不修改 camera ownership，也不重播任何 programmatic camera effect。

### Non-Goals

- 不顯示 predicted 或 pending coordinate。
- 不新增 follow-camera 模式、route history 或方向推算。
- 不改變 `SimulationStore`、`RouteSession`、mutation queue 或 transport recovery state machine。
- 不改變 A／B、preview、Mac location 與 route polyline 的 domain semantics。

## Decisions

### 1. 由專用 observation wrapper 驅動 map canvas

在 `LocationMapView.swift` 內加入小型 `@ObservedObject` wrapper，只有 `simulationStore` 存在時由它讀取 `SimulationStore.confirmedRouteMarkerCoordinate`，轉成 `MapCoordinate` 後傳給 `LocationMapCanvas`；disconnected path 傳入 `nil`。這讓 map subtree 直接訂閱 `SimulationStore.objectWillChange`，不依賴 sibling `SimulationControls` 或父層偶然重算。

`confirmedRouteMarkerCoordinate` 是 presentation-only computed projection，不保存 route progress，也不複製 snapshot：`.route` 僅在 position knowledge仍可信時回傳 snapshot coordinate；`.stopping` 僅在既有 `routeSession.interruption?.positionKnowledge != .unknown` 時回傳該session的 `confirmedCoordinate`；其他 state回傳 `nil`。兩條路徑都只讀 `RouteSession` 已由成功device mutation確認的 truth；stopping時不要求不存在的`routeSnapshot`。

### 2. marker 僅代表 confirmed coordinate

`.route` snapshot 的 `confirmedCoordinate` 非 `nil`，且 phase不是帶有 `positionKnowledge == .unknown` 的 `.interrupted` 時顯示 marker。pending mutation或recovery pending尚未publish新confirmed snapshot，因此marker自然停在最後確認位置；pause與complete保留marker。position仍可信時，stop進入`.stopping`後的clear pending或clear failure從既有route session保留最後confirmed marker，clear success轉成`.idle`才移除。若route已因position unknown中斷，後續`.stopping`仍檢查保留於`routeSession.interruption`的knowledge並維持`nil`，不得重新顯示。session replacement、point mode、沒有route或top-level interruption也回傳`nil`。

這個規則避免 UI 把尚未獲得 device acknowledgement 的座標或 position-unknown 狀態顯示為可信位置。

### 3. 以角色化 annotation registry 維持 identity

將 Coordinator 的 annotations 依固定角色管理：preview、endpoint A、endpoint B、Mac location、confirmed iPhone route location。update只新增缺少角色、更新既有 annotation 的 coordinate／title／subtitle，或移除該角色不再存在的 annotation，不再對每次 render執行全量 `removeAnnotations`。

confirmed iPhone marker使用專屬 reuse identifier、system image／glyph與 tint；標題固定為「iPhone 模擬位置」。其他角色維持目前標題與 callout 行為。

route overlay也改為identity／內容同步：route identity與polyline內容不變時保留同一個`MKPolyline`；只有route建立、內容改變或消失才新增、替換或移除。marker-only render不得執行`removeOverlays`或重建polyline。

### 4. render state 與 camera effect 完全分離

route marker coordinate更新只走 annotation sync，不呼叫 `setRegion`、`setVisibleMapRect` 或 `LocationMapCameraEffects`。route fit仍只由新的 `routeCameraIdentity` 消耗一次；Mac initial center仍只由新的 ready generation 消耗一次。annotation sync測試需直接證明反覆更新 route marker不增加 camera effect invocation。

### 5. 測試覆蓋 projection、observation 與 annotation identity

在既有 test files 內增加：

- `LocationMapModelTests.swift`：驗證角色化 annotation sync會原地更新 confirmed iPhone marker、保留其他 annotation identity、正確移除 marker，且不重播 camera effect。
- `ContentViewTests.swift`：以同一 `NSHostingView` hierarchy publish route confirmed coordinate，驗證穩定accessibility identifier與同一annotation instance的coordinate實際更新；再進入position-unknown或clear-success terminal state後消失，不得重建root view或只讀store property。
- `SimulationStoreTests.swift`：直接驗證presentation projection在running／pending／paused／completed，以及position可信的stopping／clear failure保留confirmed coordinate；route position-unknown interruption及其後續stop／clear pending／clear failure、replacement、point與idle均回傳`nil`。

不新增 test file，因此不需要修改 Xcode target membership。

## Implementation Contract

1. `LocationMapView` SHALL 在 `SimulationStore` 存在時，由直接持有 `@ObservedObject` 的 map wrapper讀取 `SimulationStore.confirmedRouteMarkerCoordinate`；MUST NOT依賴 `SimulationControls` 的 sibling observation觸發 map 更新。
2. route marker coordinate SHALL 唯一來自route已確認truth：`.route`使用`RouteSimulationSnapshot.confirmedCoordinate`，`.stopping`使用同一`RouteSession.confirmedCoordinate`；MUST NOT來自pending token、elapsed-time prediction、route polyline sampling或request coordinate。
3. confirmed coordinate首次 publish後 SHALL 顯示標題為「iPhone 模擬位置」且可與 A、B、preview與「Mac 目前位置」區分的 marker。
4. 新 confirmed coordinate SHALL 原地更新同一個 route marker annotation；MUST NOT因每秒更新而移除重建其他 annotations或未改變的route overlay。
5. mutation或transport recovery pending期間 SHALL 保持最後 confirmed marker；pause、single-trip completed，以及position knowledge仍可信的stop／clear pending及clear failure SHALL 保留 marker。
6. route `.interrupted`且`positionKnowledge == .unknown`、該route後續進入stopping／clear pending／clear failure、top-level position-unknown interruption、`.idle`、session replacement尚未確認新route coordinate、point mode或沒有`SimulationStore`時 SHALL 不顯示 route marker；clear success SHALL 以`.idle`移除marker。
7. route marker新增、移動或移除 MUST NOT觸發 route fit、preview center、Mac initial center或改變manual camera ownership。
8. `LocationMapModelTests.swift` SHALL 透過同一Coordinator同步boundary直接驗證annotation與overlay identity、所有camera effect零增量及manual interaction callback不變；`ContentViewTests.swift` SHALL 在同一`NSHostingView`內驗證穩定identifier、同一annotation instance的coordinate更新與移除；`SimulationStoreTests.swift` SHALL 驗證projection lifecycle。
9. 本 change MUST NOT修改 `SimulationStore`、`RouteSession`、device mutation或transport recovery的狀態與時序 contract。

## Risks / Trade-offs

- **annotation registry改動既有marker更新方式**：若角色同步遺漏 subtitle 或移除條件，可能留下 stale preview／endpoint。以所有角色的新增、更新、移除與 identity tests 限制風險。
- **每秒 SwiftUI invalidation增加 map render頻率**：route本來每秒 publish；wrapper只同步變動annotation，未改變的route overlay與camera保持原identity，成本有限。
- **MapKit marker動畫行為依系統版本不同**：contract只要求座標隨 confirmed state更新與 identity穩定，不要求特定動畫曲線或 duration。
- **completed marker可能被誤認為仍在移動**：completed保留於終點符合外部模擬位置仍有效的既有 semantics；使用者 stop並成功 clear後才移除。
