## 1. TDD：建立可重現的失敗測試

- [x] [P] 1.1 在 `iPhoneLocationMoveTests/LocationMapModelTests.swift` 新增 model regression tests：同一份 `searchResults` 先選位置 A 再選位置 B 皆成功、兩次 `MapPreviewCameraIntent.identity` 不同且 preview 最終為 B；重複選取同一 place 仍前進 generation；不在目前結果集合的 place 丟出 `staleSearchSelection` 且狀態不變。
- [x] [P] 1.2 在 `iPhoneLocationMoveTests/ContentViewTests.swift` 新增同一 rendered `NSHostingView<LocationMapView>` 的 regression tests：透過結果列實際 action 依序選取 A、B，驗證同一 `MKMapView` 的「預覽」annotation、目前預覽資料與 camera operation 依序更新；手動移開 camera 後再次觸發 B，驗證新的 camera operation。另建立較新的 search ownership 後觸發重繪前殘留的舊結果 action，驗證新 search／preview-address async operation 未被取消且 response 仍可套用。先確認測試在現有一次性 request guard 與 cancel-before-validation 順序下失敗。

## 2. 修正搜尋結果 selection lifecycle

- [x] 2.1 在 `iPhoneLocationMove/Features/Map/LocationMapModel.swift` 將選取入口調整為 `selectSearchResult(_:)`：以目前 `searchResults` membership 驗證候選、每次成功都呼叫既有 `advanceSearchOwnership()`、更新 `preview` 與新的 `MapPreviewCameraIntent`、清除 `activeSearchRequest` 但保留結果清單；不得以相同 coordinate 去重。
- [x] 2.2 更新 `iPhoneLocationMoveTests/LocationMapModelTests.swift` 內既有 `selectSearchResult(_:from:)` 呼叫與相關 assertion，使既有 stale response、camera precedence、直接地圖選點與 reset coverage 繼續驗證新的 model API。
- [x] 2.3 在 `iPhoneLocationMove/Features/Map/LocationMapView.swift` 移除結果列 action 對 view-local `searchRequest` 的可用性 guard；固定先呼叫 `selectSearchResult(_:)`，只有 model 成功取得目前 selection ownership 後才執行 `cancelSearch()`、`cancelPreviewAddressLookup()` 與清除 `searchRequest`，stale selection 不得取消任何較新的 async operation，並保留既有錯誤呈現。若現有 AppKit hierarchy 無法穩定觸發 production SwiftUI button，加入每列唯一 identifier 的 DEBUG-only `TestingActionMarker`，並維持零尺寸、不可 hit-test、非 accessibility element、拒絕 first responder及與可見列共用同一 action。

## 3. 驗證 contract 與回歸

- [x] 3.1 執行 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS' -only-testing:iPhoneLocationMoveTests/LocationMapModelTests -only-testing:iPhoneLocationMoveTests/ContentViewTests`，確認 model 與同一 rendered hierarchy 的搜尋結果連續／重複選取案例通過。
- [x] 3.2 執行完整 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS'`，確認 route、camera、Mac recenter、workspace reset 與其他 location simulation 行為沒有回歸。
- [x] 3.3 檢查最終 diff 僅包含 `iPhoneLocationMove/Features/Map/LocationMapModel.swift`、`iPhoneLocationMove/Features/Map/LocationMapView.swift`、`iPhoneLocationMoveTests/LocationMapModelTests.swift`、`iPhoneLocationMoveTests/ContentViewTests.swift`、本 change artifacts 與 Cash review loop 產生的 `openspec/signals/*.md`，且沒有新增 identity type、state machine、module 或 dependency。

## 4. Review follow-up：收斂測試 seam 與驗證證據

- [x] 4.1 在 `iPhoneLocationMove/Features/Map/LocationMapView.swift` 與 `iPhoneLocationMoveTests/ContentViewTests.swift` 將 cancellation observers 重新命名為 `onSearchCancellationRequested`／`onPreviewAddressCancellationRequested`，並以 `#if DEBUG` 將 stored properties、initializer parameters、assignments 與 invocation 全部排除於 Release build；成功選取仍作為 observers 已接線的 positive control。
- [x] 4.2 在 `iPhoneLocationMoveTests/ContentViewTests.swift` 的 stale rendered action tests 明確註解不得等待 SwiftUI 重繪，並至少斷言一次 `sidebar-workspace-message-region` 出現，以覆蓋 `design.md` Implementation Contract 5、10、11 與 `openspec/changes/fix-repeat-search-result-selection/specs/location-simulation/spec.md` 的「重繪前的舊結果 action 不取消較新搜尋」scenario。
- [x] 4.3 校對 `openspec/specs/location-simulation/spec.md` 的「地圖搜尋、選點與明確確認」Requirement 與本 change delta：master 既有 7 個 scenario 全數保留，delta 新增 3 個 scenario，並確認 task／diff scope 明列 Cash review loop 產生的 `openspec/signals/*.md`。
- [x] 4.4 執行 `ContentViewTests`、完整 macOS `xcodebuild test` 與 `-configuration Release` build；若完整 suite 出現與本 change 無關的 flaky failure，單獨重跑失敗案例並保留清楚驗證紀錄。
