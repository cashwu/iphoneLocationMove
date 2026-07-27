## 1. TDD：先建立可重現的失敗測試

- [x] [P] 1.1 在 `iPhoneLocationMoveTests/LocationMapModelTests.swift` 建立 failing tests，透過同一Coordinator同步boundary驗證角色化annotation以同一identity更新「iPhone 模擬位置」、保留A／B／preview／Mac annotations與未改變的route overlay、在來源消失時只移除iPhone marker；以spy證明反覆marker更新對route／preview／Mac camera operation皆為零增量，且manual interaction callback不變。
- [x] [P] 1.2 在 `iPhoneLocationMoveTests/ContentViewTests.swift` 建立 failing rendered-hierarchy tests：不重建root view，在同一個`NSHostingView`內讓`SimulationStore` publish首次及後續`confirmedCoordinate`，驗證穩定identifier `iphone-route-marker`所對應的同一annotation instance之coordinate實際更新，position-unknown或clear成功後消失；不得只搜尋identifier或讀store property。
- [x] [P] 1.3 在 `iPhoneLocationMoveTests/SimulationStoreTests.swift` 建立 failing projection tests，驗證running／mutation pending／recovery pending／paused／completed，以及position可信的stopping／clear failure保留最後confirmed route coordinate；已有confirmed coordinate的route經`handleDeviceInterruption(positionKnowledge: .unknown)`後立即回傳`nil`，且後續stop的clear pending／clear failure仍維持`nil`；replacement、point與idle亦回傳`nil`。

## 2. 實作 confirmed iPhone route marker

- [x] 2.1 在 `iPhoneLocationMove/Features/Simulation/SimulationStore.swift` 實作presentation-only computed projection `confirmedRouteMarkerCoordinate`：`.route`依phase／`positionKnowledge`過濾snapshot confirmed coordinate；`.stopping`只在`routeSession.interruption?.positionKnowledge != .unknown`時讀取同一session的confirmed coordinate，position unknown後不得因stop重新顯示；不得複製progress。再於`iPhoneLocationMove/Features/Map/LocationMapView.swift`加入直接持有`@ObservedObject SimulationStore`的小型map wrapper，將projection轉成`MapCoordinate?`傳入canvas，disconnected path傳入`nil`，使1.2與1.3通過。
- [x] 2.2 在 `iPhoneLocationMove/Features/Map/LocationMapView.swift` 將Coordinator annotation更新改為固定角色registry，為confirmed iPhone marker提供獨立reuse identifier、glyph／tint、標題與accessibility identity；同時以route identity／polyline equality同步overlay。marker-only更新只原地更新該annotation，保留其他annotations與route overlay identity，不得呼叫任何camera effect或manual interaction callback，使1.1通過。

## 3. 驗證與視覺 acceptance

- [x] 3.1 執行 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS' -only-testing:iPhoneLocationMoveTests/LocationMapModelTests -only-testing:iPhoneLocationMoveTests/ContentViewTests -only-testing:iPhoneLocationMoveTests/SimulationStoreTests`，確認marker／overlay identity、publisher invalidation、projection lifecycle與camera isolation通過。
- [x] 3.2 執行 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS'`，確認完整Swift tests無回歸。
- [x] 3.3 以正常 Apple Development簽章 build連接USB iPhone，執行一段route並目視驗證marker與 A／B／Mac位置可區分、隨confirmed update移動、pause保持、stop成功後移除，且使用者手動移動地圖後marker更新不會自動重新置中；將實際裝置、iOS版本與結果記入 `openspec/changes/show-confirmed-iphone-route-marker/implementation-notes.md`。
