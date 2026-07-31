## Summary

修正搜尋結果清單在第一次選取後仍顯示、但後續列點擊不再生效的互動缺陷。只要目前搜尋結果仍可見，每次選取任一結果（包含再次選取同一結果）都會更新 preview marker 與目前預覽內容，並以新的 camera intent 將地圖移至該結果。

## Motivation

目前第一次選取搜尋結果後，view 會清除 `searchRequest`，model 也會結束該 request 的 ownership；搜尋結果清單卻繼續顯示且外觀仍可互動。後續點擊因此被忽略，造成可見控制項與實際行為不一致，使用者會誤以為地圖或搜尋功能故障。

這是既有搜尋與預覽 contract 的 Bug Fix：可見的搜尋結果應持續可選，且每次明確點擊都應產生可觀察的 preview 與 camera 更新，不得改變 iPhone 位置。

## Proposed Solution

- 將「MapKit query response ownership」與「目前可見搜尋結果的選取有效性」分開：`MapSearchRequest` 繼續只負責拒絕 stale response；結果列是否可選則由目前 `searchResults` membership 決定。
- 搜尋結果清單仍顯示期間，允許使用者依序選取不同結果，也允許再次選取同一結果。
- 每次有效選取都遞增既有 `MapSearchGeneration`，更新 `preview`，並建立新的 `MapPreviewCameraIntent`；camera effect 仍只消耗一次，不因 annotation 或 overlay redraw 重播。
- 結果列 action 先由 model 驗證目前 `searchResults` membership 並成功取得 selection ownership，之後才取消 view-local async work；重繪前殘留的舊列 action 不得取消較新的搜尋或 reverse-geocode。
- 新搜尋、直接地圖選點、清除搜尋或 workspace reset 仍依既有規則清空／取代結果，使已不再顯示的舊結果無法被選取。
- 以 model 測試覆蓋結果 membership、generation 與重複選取，以 rendered hierarchy 測試覆蓋同一份可見清單連續點擊不同列的實際 UI 行為。

## Non-Goals

- 不變更 MapKit 搜尋排序、數量、模糊比對或網路錯誤處理。
- 不改變直接點擊地圖時保留 visible region 的行為。
- 不改變 route fit、Mac 位置置中或其他 camera effect 的 precedence。
- 不新增搜尋結果 marker；地圖仍只顯示單一 preview marker。
- 不因選取搜尋結果立即改變 iPhone 位置或自動指定 A／B。

## Alternatives Considered

- 第一次選取後直接隱藏搜尋結果清單：可避免失效控制項，但會迫使使用者為比較鄰近結果而重做相同搜尋，與目前清單持續顯示的介面意圖不符。
- 保留原本 request 作為所有後續選取的 ownership：會混合 async response freshness 與 UI selection lifecycle，使 generation 已因 preview 變更而前進後仍需特殊豁免舊 request，增加 stale response 風險。
- 為清單另建新的 identity／state machine：可以建模，但目前 `searchResults` 已是唯一可見候選集合；以 membership 作為選取邊界即可完整解決問題，新增機制沒有必要。

## Capabilities

### New Capabilities

無。

### Modified Capabilities

- `location-simulation`：補強地圖搜尋結果的重複選取 contract，要求目前仍顯示的每個結果在每次點擊時都更新 preview，並取得一次新的 preview camera intent。

## Impact

- Affected specs:
  - `openspec/specs/location-simulation/spec.md`
- Affected code:
  - New:
    - (none)
  - Modified:
    - `iPhoneLocationMove/Features/Map/LocationMapModel.swift`
    - `iPhoneLocationMove/Features/Map/LocationMapView.swift`
    - `iPhoneLocationMoveTests/LocationMapModelTests.swift`
    - `iPhoneLocationMoveTests/ContentViewTests.swift`
  - Removed:
    - (none)
