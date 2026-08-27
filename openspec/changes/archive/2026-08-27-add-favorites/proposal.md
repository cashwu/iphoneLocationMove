## Summary

在 Mac 端地圖側欄加入「我的最愛」：使用者可把已確認的預覽點（搜尋選取或地圖點選後的點位，也就是「設定位置」實際送出的目標點）收藏起來，之後從最愛清單一鍵回到該點位，直接進行「設為 A / 設為 B / 設定位置」。收藏可取消（preview 面板 toggle 與清單逐筆刪除）、可重新命名，並以 `UserDefaults` 持久化跨啟動保留。

## Motivation

目前每次要把 iPhone 移動到常用點位（家、公司、常測試的地標），都必須重新搜尋或在地圖上重新點選。搜尋結果沒有任何跨啟動記憶，重複操作成本高。程式上「搜尋過的點位」與「移動過去的目標點位」已收斂於同一個狀態（`LocationMapModel.preview`），只要對 preview 提供收藏與回選能力，就能同時涵蓋兩個使用情境。

## Proposed Solution

1. **收藏資料與持久化**：新增 `FavoritesStore`（`ObservableObject`），比照 `RiskNoticeStore` 注入 `UserDefaults` 的模式，由 app shell（`AppDelegate`）持有單一實例注入地圖側欄，以 Codable DTO 的 JSON 形式儲存收藏清單。每筆收藏包含 UUID、座標、地址快照、使用者可改名稱（預設為地址或座標文字）與加入時間。載入採逐元素 lossy decode 並逐筆驗證座標（範圍沿用 `MapCoordinate` 規則），單筆無法解碼或無效的項目跳過，不因單筆壞資料丟棄整份清單。
2. **收藏入口（toggle）**：preview 面板加入收藏按鈕。當前 preview 座標尚未收藏時顯示「加入最愛」，已收藏（座標完全相等判定）時顯示「取消最愛」，按下即加入或移除。重複加入不會產生第二筆。
3. **最愛清單**：側欄新增「我的最愛」區塊，依加入時間排序，每列可點選、可重新命名、可刪除。
4. **選用最愛**：點選最愛等同選取一筆已知地址的搜尋結果——由 `LocationMapModel` 新增的選用入口推進 `mapSearchGeneration`、設定 `preview`（含地址快照）與 `previewCameraIntent`（以新 generation 作為 identity），清空搜尋結果與 in-flight 搜尋 ownership。之後「設為 A / 設為 B / 設定位置」走既有流程，不新增平行選點路徑。
5. **行為邊界**：取消最愛不影響任何進行中的狀態（當前 preview、A/B 端點、模擬目標維持原樣）；「工作區重置」不清除最愛清單（最愛是持久化書籤，屬於「App 剛啟動的狀態」的一部分）。

## Non-Goals

- 不收藏路線模擬進行中的即時位置（只收藏已確認的目標點位）。
- 不做資料夾、標籤、拖曳排序。
- 不做 iCloud 或跨機同步、匯入匯出。
- 不修改既有搜尋、選點、A/B 路線與模擬的行為契約。

## Alternatives Considered

- **在搜尋結果列表逐筆加收藏鈕**：入口分散且會收藏未確認的點位；使用者實際想收藏的是「選定後的那個點」，統一在 preview 面板一個入口即可涵蓋搜尋與移動目標兩個情境。
- **收藏模擬中的即時位置**：需要從 `SimulationStore` 取動態座標並定義行進中座標的快照語義，範圍明顯變大且使用情境不明確，列為 Non-Goal。
- **以檔案（Application Support）或 `NSUbiquitousKeyValueStore` 持久化**：收藏量預期為個位數到數十筆的小型清單，`UserDefaults` + Codable DTO 與既有 `RiskNoticeStore` 注入模式一致、測試成本最低；未來若需要同步再遷移。
- **由 `LocationMapView` 以 `@StateObject` 各自持有 `FavoritesStore`**：App 支援多個主視窗（選單「開啟定位控制」⌘0），兩個視窗各持一個 store 實例會對同一份持久化資料 last-writer-wins 覆寫，造成收藏靜默遺失，且清單 UI 不跨視窗同步；故改由 `AppDelegate` 持有單一實例（比照既有 `riskNoticeStore` 模式）注入。

## Capabilities

### New Capabilities

- `favorite-places`：我的最愛點位——收藏（toggle 去重）、取消（面板 toggle 與清單刪除）、重新命名、持久化與載入驗證、選用最愛回到 preview 流程、與工作區重置／進行中狀態的行為邊界。

### Modified Capabilities

（無——選用最愛重用既有 preview 確認流程，不改變 `location-simulation` 既有 requirement 的行為契約。）

## Impact

- Affected specs:
  - openspec/specs/favorite-places/spec.md（新增，經由本 change 的 delta spec）
- Affected code:
  - New:
    - iPhoneLocationMove/Features/Favorites/FavoritesStore.swift
    - iPhoneLocationMoveTests/FavoritesStoreTests.swift
  - Modified:
    - iPhoneLocationMove/Features/Map/LocationMapModel.swift
    - iPhoneLocationMove/Features/Map/LocationMapView.swift
    - iPhoneLocationMove/App/iPhoneLocationMoveApp.swift
    - iPhoneLocationMove/ContentView.swift
    - iPhoneLocationMove.xcodeproj/project.pbxproj
    - iPhoneLocationMoveTests/LocationMapModelTests.swift
    - iPhoneLocationMoveTests/ContentViewTests.swift
  - Removed:
    - (none)
