## Context

「搜尋過的點位」與「設定手機移動過去的目標點位」在現有程式中收斂於同一狀態：`LocationMapModel.preview`（`iPhoneLocationMove/Features/Map/LocationMapModel.swift`）。搜尋選取經 `selectSearchResult`、地圖點選經 `selectMapCoordinate` 設定 preview；「設定位置」按鈕直接讀取 `preview` 的座標送出。preview 的所有權以 `mapSearchGeneration`（單調遞增 generation）防護 stale 選取與 stale 非同步回應。既有持久化模式為 `RiskNoticeStore`：注入 `UserDefaults` 的 `@MainActor ObservableObject`，由 `AppDelegate` 持有單一實例（`iPhoneLocationMove/App/iPhoneLocationMoveApp.swift`）。App 以 `WindowGroup` 呈現主視窗且選單提供「開啟定位控制」（⌘0），同一時間可存在多個主視窗。Xcode 專案由 XcodeGen 管理（`iPhoneLocationMove/project.yml`，targets 以目錄掃描收檔：`path: iPhoneLocationMove` 與 `path: iPhoneLocationMoveTests`），`project.pbxproj` 是 regen 產物；新增 source／test 檔案落在掃描目錄內即會於 regen 時納入 target。

## Goals / Non-Goals

Goals：

- 收藏已確認的 preview 點位，跨啟動保留。
- preview 面板單一 toggle 入口（加入／取消），座標完全相等視為同一收藏。
- 最愛清單：點選回到 preview 流程、重新命名、逐筆刪除，依加入順序呈現。
- 選用最愛重用既有 generation 機制，不新增平行選點路徑。

Non-Goals：

- 不收藏模擬進行中的即時位置；不做資料夾、標籤、排序拖曳、同步、匯入匯出。
- 不修改 `location-simulation` 既有 requirement 的行為契約（搜尋、A/B、路線、重置流程不變）。

## Decisions

1. **`FavoritesStore` 為唯一收藏 owner，由 app shell 持有單一實例**：新檔 `iPhoneLocationMove/Features/Favorites/FavoritesStore.swift`，`@MainActor final class FavoritesStore: ObservableObject`，注入 `UserDefaults`（預設 `.standard`）。實例由 `AppDelegate` 持有（比照既有 `riskNoticeStore`），經 `ContentView` → `LocationWorkspaceView` → `LocationMapView` 注入。App 支援多個主視窗（⌘0），單一實例確保所有視窗觀察同一份清單，避免兩個 store 實例對同一 key 的 last-writer-wins 覆寫造成收藏靜默遺失。清單以 JSON 編碼的 DTO 陣列存於單一 key。`LocationMapModel` 不知道收藏存在。
2. **持久化 DTO 與逐元素 lossy decode**：DTO 為 `Codable` 純資料（`id`、`latitude`、`longitude`、`address`、`name`、`addedAt`）。載入採逐元素 lossy decode（unkeyed container 對每個元素 `try?` decode）：單筆欄位毀損或無法解碼即跳過該筆，其餘保留；成功 decode 的元素再經 `MapCoordinate` 的 throwing init 驗證座標，失敗同樣跳過。只有整份資料非合法清單結構時才以空清單啟動。儲存於每次變更後同步寫回。
3. **去重與 toggle 語義**：以 `MapCoordinate` 的 `Equatable`（Double 完全相等）判定「已收藏」。toggle：已存在 → 移除該筆；不存在 → 以預設名稱新增。預設名稱 = 地址快照；地址為 nil 時用座標文字：緯度、經度各以四捨五入取小數 5 位（等同 `String(format: "%.5f")`），以「, 」連接。
4. **選用最愛走既有 generation 機制**：`LocationMapModel` 新增 `selectFavorite(_ place: MapSearchPlace) throws`——推進 `mapSearchGeneration`、`preview = place`（含地址快照）、`previewCameraIntent = MapPreviewCameraIntent(coordinate: place.coordinate, identity: 新 generation)`、清空 `searchResults` 與 `activeSearchRequest`、記錄使用者地圖脈絡（`recordUserMapContext()`）。camera intent 的 identity 是新 generation 而非座標：重複選同一筆最愛必定產生新 intent，回到相同座標仍會置中（對應 open signal `preview-camera-coordinate-dedup`）。既有 `beginSearch`／`clearSearch`／`selectMapCoordinate`／`resetWorkspace` 清除 `previewCameraIntent` 的路徑不變（對應 `preview-camera-intent-stale-clear`）。
5. **View 端順序：先過 model ownership gate，再取消 view-local async**：最愛列的點選 action 先呼叫 `model.selectFavorite`，成功後才取消 view 持有的 in-flight search／reverse-geocode task（對應 `stale-view-action-cancels-current-request`）。`selectFavorite` 推進 generation 後，舊 search／geocode 回應由既有 stale 判定自然作廢。
6. **View 結構與觀察邊界**：`LocationMapView` 以必要參數 `favoritesStore: FavoritesStore` 注入並以 `@ObservedObject` 持有（實例擁有權在 `AppDelegate`，view 只觀察）。preview 面板 toggle 按鈕與「我的最愛」清單區塊都在 `LocationMapView` 內直接觀察同一個 store 實例，無 sibling 派生輸入問題（對應 `swiftui-sibling-observation-boundary`）。toggle 按鈕加 `testingLayoutRegion("sidebar-button-favorite-toggle")`，清單區塊加 `testingLayoutRegion("sidebar-favorites-list")`。
7. **重新命名互動**：每列提供右鍵選單「重新命名」「刪除」。重新命名把該列切換為行內 `TextField`；編輯模式下該列的選用（點選）action 停用。submit 是唯一提交路徑：名稱先 trim 空白，trim 後為空字串則不變更原名稱；Esc 或失焦離開編輯模式時丟棄 pending 文字、回顯原名。
8. **行為邊界**：`FavoritesStore` 的任何變更（含刪除當前 preview 對應的收藏）不觸碰 `LocationMapModel` 狀態；`resetWorkspace()` 不觸碰 `FavoritesStore`。兩者間唯一的資料流是 view 端的 `selectFavorite` 呼叫與 `isFavorite` 查詢。
9. **專案註冊採 XcodeGen regen**：`FavoritesStore.swift` 與 `FavoritesStoreTests.swift` 落在 `project.yml` 既有目錄掃描範圍內，不需修改 `project.yml`；新增檔案後依 README 既有流程執行 xcodegen generate --spec iPhoneLocationMove/project.yml --project . --project-root . 重新產生 `project.pbxproj`。regen diff 檢查：只允許新檔 registration 與 generator 既有的無關緊要正規化，不得夾帶未宣告的 resources、build defaults、scheme churn 或個人 workspace 狀態（對應 `xcodegen-regeneration-scope-drift`、`generated-user-state-scope-drift`、`xcode-test-file-target-membership`）。

## Implementation Contract

型別與 API（`iPhoneLocationMove/Features/Favorites/FavoritesStore.swift`）：

- `struct FavoritePlace: Equatable, Identifiable, Sendable` — `let id: UUID`、`let coordinate: MapCoordinate`、`let address: String?`、`var name: String`、`let addedAt: Date`。
- `@MainActor final class FavoritesStore: ObservableObject`：
  - `static let defaultsKey = "favoritePlaces"`
  - `init(defaults: UserDefaults = .standard)` — 依 Decisions 第 2 點載入。
  - `@Published private(set) var favorites: [FavoritePlace]` — 順序即事實來源：新增一律 append，持久化與載入保持陣列順序，不重排（`addedAt` 隨附記錄，加入時間順序由 append 自然成立）。
  - `func isFavorite(_ coordinate: MapCoordinate) -> Bool`
  - `func toggle(_ place: MapSearchPlace)` — 已收藏（座標相等）→ 移除；未收藏 → append 新增（`id` 新 UUID、`name` 預設規則、`addedAt` 當下時間）。
  - `func remove(id: UUID)` — 不存在時為 no-op。
  - `func rename(id: UUID, to name: String)` — trim 後為空或 id 不存在時為 no-op。
  - 每次變更後以 JSON 寫回 `defaultsKey`。持久化路徑不得含 `try!` 或 `fatalError`；持久化寫入結果不影響 `favorites` 的記憶體狀態（以寫入丟棄型 `UserDefaults` 子類可驗證）。

`AppDelegate`（`iPhoneLocationMove/App/iPhoneLocationMoveApp.swift`）：

- 新增 `let favoritesStore = FavoritesStore()`（比照既有 `riskNoticeStore`）。

`ContentView`／`LocationWorkspaceView`（`iPhoneLocationMove/ContentView.swift`）：

- `LocationWorkspaceView` 新增 `favoritesStore` 參數；`ContentView` 以 `appDelegate.favoritesStore` 傳入，向下傳給 `LocationMapView`。

`LocationMapModel`（`iPhoneLocationMove/Features/Map/LocationMapModel.swift`）：

- `func selectFavorite(_ place: MapSearchPlace) throws` — 行為如 Decisions 第 4 點；唯一 throw 來源是 generation 耗盡（`LocationMapError.identityExhausted`），exhaustion 行為由 `MapSearchGeneration.advanced()` 既有型別層契約保證。不驗證 place 是否仍在收藏清單（刪除後殘留列的點選仍是合法座標選取）。

`LocationMapView`（`iPhoneLocationMove/Features/Map/LocationMapView.swift`）：

- 兩個既有 init 各加必要參數 `favoritesStore: FavoritesStore`，以 `@ObservedObject` 持有。
- preview 面板：`model.preview` 非 nil 時顯示 toggle 按鈕，標題由 `favoritesStore.isFavorite(preview.coordinate)` 決定（「加入最愛」／「取消最愛」），action 呼叫 `favoritesStore.toggle(preview)`。
- 「我的最愛」區塊：`favorites` 非空時顯示，依 `favorites` 既有順序渲染（view 不自行排序）；每列點選 action 依 Decisions 第 5 點順序執行；右鍵選單提供重新命名與刪除，編輯互動依 Decisions 第 7 點。

## Risks / Trade-offs

- **Double 完全相等去重**：極近但不同的座標會成為兩筆收藏。可接受——收藏來源是同一 preview 狀態的回選，同點重複收藏必然座標相同；不引入 epsilon 以避免「距離多近算同一點」的新規則。
- **`UserDefaults` 容量**：清單預期數十筆內，JSON 體積極小；若未來要同步或大量收藏，DTO 已與 domain 型別分離，可平移到檔案儲存。
- **重複選同一最愛會重複置中**：這是刻意行為（與重複搜尋同地點一致），符合 `preview-camera-coordinate-dedup` signal 的教訓。
- **DTO 無版本欄位**：整份資料非合法清單結構時歸零為空清單，且下一次變更會覆寫舊資料——這是刻意取捨；逐元素 lossy decode 已把毀損影響縮到單筆，未來 schema 演進時再引入版本欄位。
- **地址快照語義**：地圖點選在 reverse geocode 回應前收藏的項目 address 為 nil，之後選用該最愛不會補查地址（`selectFavorite` 不發起 geocode）——收藏當下沒有地址就維持沒有，屬刻意的快照語義，不為此擴充 geocode 重查路徑。
- **rename no-op 語義**：trim 後為空不報錯而是靜默保留原名，UI 無錯誤顯示成本；風險是使用者可能以為已清空名稱，以行內 TextField 立即回顯原名緩解。
