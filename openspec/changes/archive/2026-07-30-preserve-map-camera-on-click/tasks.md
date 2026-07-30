## 1. Regression Tests

- [x] 1.1 在 `iPhoneLocationMoveTests/LocationMapModelTests.swift` 先建立 failing model transition tests：搜尋成功以新的 `MapSearchGeneration` 建立 `MapPreviewCameraIntent`；直接選點成功清除 intent；`beginSearch`、`clearSearch` 與 Reset 清除 intent；reverse geocode 保留 intent；validation failure 保留原 intent。
- [x] 1.2 在 `iPhoneLocationMoveTests/LocationMapModelTests.swift` 擴充 `CameraOperationSpyMapView`，分別計數 `setRegion`、`setCenter` 與 `setVisibleMapRect`；建立 failing canvas boundary tests，驗證直接點擊 preview、reverse-geocode address redraw，以及點擊後晚到的 stale search response 被忽略時的三種 camera operation counts及 visible region皆不變，搜尋 preview 則置中一次且 redraw 不重播。（覆蓋：`直接點擊地圖`；Example：`放大後連續選點維持相同視野`；`搜尋並預覽地點`；`點擊地圖後舊搜尋結果晚到`）
- [x] 1.3 在 `iPhoneLocationMoveTests/LocationMapModelTests.swift` 建立 failing precedence／identity tests：「搜尋 A → 直接點擊 B → 再搜尋 A」的第二個 intent 使用新 identity 並再次置中；新 route identity 與搜尋 intent 同時存在時只執行 route fit，第二次無關 redraw不得延遲重播 preview；已消耗 route identity後才產生的新搜尋 intent仍置中。（覆蓋：`回到相同搜尋座標仍重新置中`；`既有路線不遮蔽後續搜尋置中`；`新路線優先且搜尋 intent 不延遲重播`）

## 2. Implementation

- [x] 2.1 在 `iPhoneLocationMove/Features/Map/LocationMapModel.swift` 定義使用既有 `MapSearchGeneration` identity 的 `MapPreviewCameraIntent` 與 read-only published `previewCameraIntent`；在 `selectSearchResult`、`selectMapCoordinate`、`beginSearch`、`clearSearch`、`receivePreviewAddress` 與 Reset依 Implementation Contract維護 transition，且 validation failure不得提前改變 intent。
- [x] 2.2 在 `iPhoneLocationMove/Features/Map/LocationMapView.swift` 將 optional `model.previewCameraIntent` 傳入 `ObservedSimulationMapCanvas`、`LocationMapCanvas` 與 `Coordinator.update`；annotation 永遠依 `preview` 同步，但只有 intent 非 `nil` 時才透過 `LocationMapCameraEffects.applyPreview` 執行 `centerMap(on:)`。
- [x] 2.3 在 `iPhoneLocationMove/Features/Map/LocationMapView.swift` 讓 `LocationMapCameraEffects.applyPreview` 以 intent 的 `MapSearchGeneration` 去重，新增不執行 camera mutation的 `consumePreview(_:)`，並讓 `applyRoute` 回傳本次是否套用新的 route identity；Coordinator 對新 route fit維持最高優先權並消耗同輪 preview identity，route identity已消耗後才產生的新搜尋 intent則不得被既有 overlay遮蔽；Mac initial center 的 gate 維持 `preview == nil` 且僅在本輪未套用 route fit 也未套用 preview center 時評估，Mac recenter contract不變。

## 3. Verification

- [x] 3.1 執行 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:iPhoneLocationMoveTests/LocationMapModelTests`，確認 map-click camera isolation、搜尋 preview camera 與既有 camera effect gate tests 全部通過。
- [x] 3.2 執行 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`，確認完整 macOS test suite 無回歸，且不需要實體 iPhone 或 root。
