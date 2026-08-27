# favorite-places Specification

## Purpose

favorite-places capability.

## Requirements

### Requirement: 收藏已確認的預覽點位

系統 SHALL 在 Mac 端地圖側欄的 preview 面板提供單一收藏 toggle 按鈕，作用於當前已確認的預覽點（搜尋選取或地圖點選後的 `preview`）。當前 preview 座標不在最愛清單時按鈕 SHALL 顯示加入語義，按下後以該點的座標、地址快照與預設名稱新增一筆收藏；已在清單時按鈕 SHALL 顯示取消語義，按下後移除該筆收藏。「已收藏」判定 MUST 以座標完全相等為準；重複加入 MUST NOT 產生第二筆。預設名稱 SHALL 為地址快照；地址不存在時 SHALL 為緯度、經度各取小數 5 位的座標文字。

#### Scenario: 加入最愛

- **GIVEN** 使用者搜尋並選取「台北101」，preview 顯示該點
- **AND** 該座標不在最愛清單
- **WHEN** 使用者按下收藏按鈕
- **THEN** 最愛清單新增一筆，名稱預設為該點地址快照
- **AND** 按鈕切換為取消語義

#### Scenario: 取消最愛

- **GIVEN** 當前 preview 座標已在最愛清單
- **WHEN** 使用者按下收藏按鈕
- **THEN** 該筆收藏自清單移除
- **AND** 按鈕切換為加入語義

#### Scenario: 重複加入不產生重複項

- **GIVEN** 座標 (25.033964, 121.564468) 已在最愛清單
- **WHEN** 使用者再次對同座標的 preview 執行加入
- **THEN** 清單中該座標仍只有一筆

##### Example: 無地址時的預設名稱

- preview 為地圖點選、reverse geocode 尚未回應：座標 (25.033964, 121.564468)、地址為空
- 按下收藏後，該筆名稱為「25.03396, 121.56447」

<!-- @trace
source: add-favorites
updated: 2026-08-27
code:
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/App/iPhoneLocationMoveApp.swift
  - iPhoneLocationMove/ContentView.swift
  - iPhoneLocationMove/Features/Favorites/FavoritesStore.swift
  - iPhoneLocationMove/Features/Map/LocationMapModel.swift
  - iPhoneLocationMove/Features/Map/LocationMapView.swift
  - iPhoneLocationMoveTests/ContentViewTests.swift
  - iPhoneLocationMoveTests/FavoritesStoreTests.swift
  - iPhoneLocationMoveTests/LocationMapModelTests.swift
tests:
-->

### Requirement: 我的最愛清單

系統 SHALL 在地圖側欄提供「我的最愛」清單區塊，最愛清單非空時顯示所有收藏，依加入時間遞增排序。每列 SHALL 提供重新命名與刪除操作：重新命名以行內編輯提交，提交值 MUST 先 trim 前後空白，trim 後為空字串時 MUST NOT 變更原名稱；刪除 SHALL 只移除該筆收藏。

#### Scenario: 依加入時間排序

- **GIVEN** 使用者依序收藏「公司」「家」「健身房」
- **WHEN** 檢視我的最愛清單
- **THEN** 清單順序為「公司」「家」「健身房」

#### Scenario: 重新命名

- **GIVEN** 一筆名稱為「台北市信義區信義路五段7號」的收藏
- **WHEN** 使用者重新命名為「公司」並提交
- **THEN** 該列顯示「公司」，座標與地址快照不變

#### Scenario: 空白名稱不變更

- **GIVEN** 一筆名稱為「公司」的收藏
- **WHEN** 使用者提交只含空白的名稱
- **THEN** 該筆名稱維持「公司」

#### Scenario: 刪除單筆

- **GIVEN** 清單有三筆收藏
- **WHEN** 使用者刪除第二筆
- **THEN** 清單剩兩筆，其餘各筆內容與順序不變

<!-- @trace
source: add-favorites
updated: 2026-08-27
code:
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/App/iPhoneLocationMoveApp.swift
  - iPhoneLocationMove/ContentView.swift
  - iPhoneLocationMove/Features/Favorites/FavoritesStore.swift
  - iPhoneLocationMove/Features/Map/LocationMapModel.swift
  - iPhoneLocationMove/Features/Map/LocationMapView.swift
  - iPhoneLocationMoveTests/ContentViewTests.swift
  - iPhoneLocationMoveTests/FavoritesStoreTests.swift
  - iPhoneLocationMoveTests/LocationMapModelTests.swift
tests:
-->

### Requirement: 選用最愛回到預覽流程

系統 SHALL 讓使用者點選最愛清單中的一筆後回到既有的 preview 確認流程：該點（含地址快照）成為當前 preview、地圖鏡頭置中到該座標，且後續「設為 A」「設為 B」「設定位置」走既有流程。選用最愛 MUST 推進既有的搜尋 generation 使 in-flight 的搜尋與 reverse geocode 回應判定為 stale 而不套用，並 MUST 清空當前搜尋結果列表。鏡頭置中的 intent identity MUST 使用推進後的新 generation；重複選用同一筆最愛 MUST 每次都產生新的置中 intent。選用最愛 MUST NOT 要求該筆仍存在於清單（點選後才被移除的殘留列視為合法座標選取）。

#### Scenario: 點選最愛設定 preview 並置中

- **GIVEN** 一筆名稱為「公司」、含地址快照的收藏
- **WHEN** 使用者點選該列
- **THEN** preview 顯示該點與其地址快照
- **AND** 地圖鏡頭置中到該座標
- **AND** 「設為 A」「設為 B」「設定位置」可依既有流程操作

#### Scenario: 選用最愛使 in-flight 搜尋回應失效

- **GIVEN** 一個搜尋要求尚未完成
- **WHEN** 使用者點選一筆最愛
- **AND** 之後舊搜尋要求的回應才到達
- **THEN** 該回應被判定 stale 而不套用
- **AND** 搜尋結果列表為空

#### Scenario: 重複選用同一筆最愛仍置中

- **GIVEN** 使用者點選最愛「公司」後手動拖動地圖到其他區域
- **WHEN** 使用者再次點選最愛「公司」
- **THEN** 地圖鏡頭再次置中到該座標

<!-- @trace
source: add-favorites
updated: 2026-08-27
code:
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/App/iPhoneLocationMoveApp.swift
  - iPhoneLocationMove/ContentView.swift
  - iPhoneLocationMove/Features/Favorites/FavoritesStore.swift
  - iPhoneLocationMove/Features/Map/LocationMapModel.swift
  - iPhoneLocationMove/Features/Map/LocationMapView.swift
  - iPhoneLocationMoveTests/ContentViewTests.swift
  - iPhoneLocationMoveTests/FavoritesStoreTests.swift
  - iPhoneLocationMoveTests/LocationMapModelTests.swift
tests:
-->

### Requirement: 最愛清單持久化與載入驗證

系統 SHALL 把最愛清單持久化，使收藏跨 App 重啟保留。載入時系統 MUST 逐筆驗證：單筆無法解碼或座標驗證失敗的項目 SHALL 跳過且不影響其餘項目；整份資料非合法清單結構時 SHALL 以空清單啟動。持久化寫入失敗 MUST NOT 造成 crash，記憶體內清單狀態 SHALL 維持。

#### Scenario: 跨重啟保留

- **GIVEN** 使用者收藏兩筆點位後關閉 App
- **WHEN** 重新啟動 App
- **THEN** 我的最愛清單顯示同樣兩筆，順序不變

#### Scenario: 載入時跳過無效項目

- **GIVEN** 持久化資料含三筆，其中一筆緯度為 91（超出合法範圍）
- **WHEN** App 啟動載入
- **THEN** 清單只載入其餘兩筆合法項目

<!-- @trace
source: add-favorites
updated: 2026-08-27
code:
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/App/iPhoneLocationMoveApp.swift
  - iPhoneLocationMove/ContentView.swift
  - iPhoneLocationMove/Features/Favorites/FavoritesStore.swift
  - iPhoneLocationMove/Features/Map/LocationMapModel.swift
  - iPhoneLocationMove/Features/Map/LocationMapView.swift
  - iPhoneLocationMoveTests/ContentViewTests.swift
  - iPhoneLocationMoveTests/FavoritesStoreTests.swift
  - iPhoneLocationMoveTests/LocationMapModelTests.swift
tests:
-->

### Requirement: 最愛與進行中狀態的行為邊界

最愛是持久化書籤：對最愛清單的任何變更（加入、取消、重新命名、刪除）MUST NOT 影響當前 preview、A/B 端點、路線預覽或進行中的模擬。既有「工作區重置」流程 MUST NOT 清除最愛清單。

#### Scenario: 取消最愛不影響當前 preview

- **GIVEN** 當前 preview 座標已收藏，且該點已被「設定位置」送出為模擬目標
- **WHEN** 使用者取消該筆最愛
- **THEN** preview 維持顯示、模擬不中斷
- **AND** 「設定位置」仍可依既有流程操作

#### Scenario: 工作區重置保留最愛

- **GIVEN** 最愛清單有兩筆收藏，且使用者已設定搜尋、A/B 端點與路線
- **WHEN** 使用者確認「Reset」
- **THEN** 搜尋、preview、A/B 端點與路線依既有流程清空
- **AND** 我的最愛清單仍為原本兩筆

<!-- @trace
source: add-favorites
updated: 2026-08-27
code:
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/App/iPhoneLocationMoveApp.swift
  - iPhoneLocationMove/ContentView.swift
  - iPhoneLocationMove/Features/Favorites/FavoritesStore.swift
  - iPhoneLocationMove/Features/Map/LocationMapModel.swift
  - iPhoneLocationMove/Features/Map/LocationMapView.swift
  - iPhoneLocationMoveTests/ContentViewTests.swift
  - iPhoneLocationMoveTests/FavoritesStoreTests.swift
  - iPhoneLocationMoveTests/LocationMapModelTests.swift
tests:
-->
