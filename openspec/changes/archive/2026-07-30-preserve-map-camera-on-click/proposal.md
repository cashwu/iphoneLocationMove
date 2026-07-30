## Summary

修正使用者放大或平移地圖後直接點擊選點時，preview camera 被固定 1,500 公尺 region 覆寫，導致地圖縮回既定比例的問題。直接地圖選點只更新 preview 內容，保留點擊當下的完整 camera 視野。分離 render state 與 camera intent 時，preview camera effect 的去重依據一併從 coordinate 改為 `MapSearchGeneration` identity，camera precedence 也改以本輪是否實際套用 route fit 判斷，使搜尋置中不再被相同座標或既有 overlay 錯誤抑制。

## Motivation

目前 `LocationMapCanvas.Coordinator.update` 在 preview coordinate 改變後會透過 `LocationMapCameraEffects.applyPreview` 呼叫固定 region 的 `centerMap(on:)`。使用者為了精準放置位置先放大地圖，點擊後卻立即失去該縮放脈絡，必須重複放大，直接妨礙核心選點流程。

這是既有直接選點行為的 Bug Fix：選點本應只更新 preview marker、地址與座標，不應意外取得 camera ownership 並覆寫使用者已建立的視野。

## Proposed Solution

- 由既有 `LocationMapModel` 明確區分「地圖直接點擊產生的 preview」與帶有 `MapSearchGeneration` identity、需要程式化置中的搜尋 preview camera intent。
- 地圖點擊完成後更新 preview marker、地址與座標，但不平移、不置中、不縮放 camera；點擊前後的 visible region 保持一致。
- 搜尋結果選取仍將地圖移至搜尋結果，並把 preview camera effect 的去重依據從 coordinate 改為 `MapSearchGeneration` identity，使回到相同座標的新搜尋仍會置中。
- camera precedence 改以「本輪是否實際套用 route fit」判斷：新 route identity 仍優先，但已消耗的 route identity 不再因 overlay 仍存在而遮蔽後續搜尋置中。
- route fit 自身的 fit 行為與 identity、Mac 初始置中、「到 Mac 位置」與 Reset camera 行為維持不變。
- 延伸既有 `LocationMapCameraEffects`／canvas boundary 測試，直接驗證 map click preview 不執行 camera operation，並驗證其他 programmatic camera intent 未受影響。

## Non-Goals

- 不持久化 camera 狀態；跨 App 重啟、視窗重建，或裝置就緒使 `simulationStore` 由 `nil` 變為非 `nil`、導致 map canvas 變體切換而重建 `MKMapView` 時，不保證保留視野。
- 不改變 route fit 自身的 fit 行為與 identity、Mac 初始置中、「到 Mac 位置」或 Reset 的 camera contract。
- 不改變 preview reverse geocoding、A/B 指派或 iPhone 模擬位置流程。
- 不新增 camera 模式、使用者偏好或可配置縮放值。

## Alternatives Considered

- 將所有 preview 置中改為沿用目前 span：會連帶改變搜尋結果選取的既有 camera 行為，範圍過大。
- 點擊後保留 zoom 但把座標移到中央：仍會不必要地平移使用者已建立的視野；點擊位置本來已在可視範圍內。
- 儲存並在更新後還原 camera region：會造成額外 camera 操作與 delegate callback，增加誤判手動／程式化 interaction 的風險。

## Capabilities

### New Capabilities

- (none)

### Modified Capabilities

- `location-simulation`：直接點擊地圖選點 SHALL 保留點擊當下的 camera 視野，不得因 preview 更新執行平移、置中或縮放。
- `location-simulation`：搜尋結果選取的 preview center SHALL 以 `MapSearchGeneration` identity 套用一次，回到相同座標的新搜尋 SHALL 重新置中。
- `location-simulation`：camera precedence SHALL 依本輪是否實際套用 route fit 判斷；已消耗的 route identity MUST NOT 因 overlay 仍存在而遮蔽新的搜尋 camera intent。route fit 自身行為、Mac 初始置中、「到 Mac 位置」與 Reset 的 camera contract 保持不變。

## Impact

- Affected specs:
  - openspec/specs/location-simulation/spec.md
- Affected code:
  - New:
    - (none)
  - Modified:
    - iPhoneLocationMove/Features/Map/LocationMapModel.swift
    - iPhoneLocationMove/Features/Map/LocationMapView.swift
    - iPhoneLocationMoveTests/LocationMapModelTests.swift
  - Removed:
    - (none)
