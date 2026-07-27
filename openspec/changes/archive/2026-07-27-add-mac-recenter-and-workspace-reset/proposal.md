## Summary

在地圖控制欄新增兩顆按鈕：「到 Mac 位置」把地圖鏡頭置中到 Mac 目前位置（不改變任何預覽點或 iPhone 定位）；「Reset」在使用者確認後，把 Mac 端地圖工作區（搜尋、預覽、A/B 端點、路線預覽與狀態、步行速度、往返循環、訊息、鏡頭）重置到剛開啟 App 的初始狀態，並同時停止進行中的 iPhone 模擬定位。clear 失敗時不掩蓋失敗狀態，保留既有的清理重試路徑。

## Motivation

目前 Mac 位置只在裝置就緒後自動置中一次；一旦使用者操作過地圖（`userHasMapContext`），就沒有任何方式把視角帶回 Mac 目前位置，找回自身位置只能手動平移縮放。另外，使用者建立過搜尋、預覽、A/B 端點與路線後，想「從頭來過」必須逐項清除：清除搜尋、重新指定端點、手動拉回速度滑桿、另外按停止模擬，步驟繁瑣且容易漏。這兩個都是高頻的基本操作，值得各自一顆按鈕。

## Proposed Solution

1. **「到 Mac 位置」按鈕**：位於地圖控制欄。按下後把地圖 camera 置中到 `LocationMapModel.macLocationCoordinate`；只移動視角，不建立預覽點、不改變 A/B 端點、不觸發任何 iPhone 定位變更。Mac 位置尚未取得時按鈕 disabled。置中沿用既有的「帶 identity 的 camera intent + `LocationMapCameraEffects` 去重」模式，每按一次產生一個新的可消耗 identity，套用一次後不因 annotation redraw 重播；程式化置中不得被誤判為使用者手動操作。
2. **「Reset」按鈕**：位於地圖控制欄。按下後一律先跳確認對話框：模擬進行中使用 clear 語義警語（說明只有手機回覆 clear 成功才算恢復真實定位），模擬未進行時使用輕量警語（說明會清除已建立的路線設定）。確認後：
   - Mac 端工作區立即重置：搜尋框與結果、預覽點、A/B 端點、路線預覽與 `routeStatus`、步行速度回預設 4.5 km/h、往返循環 toggle 關閉、錯誤訊息清空、地圖鏡頭回到 Mac 目前位置（可取得時）。
   - 同時取消所有 in-flight 的 search／geocode／directions 要求；generation 計數器不歸零，改以 advance 方式作廢舊回應，維持既有 stale-guard 設計。
   - 若 iPhone 模擬持有清理責任（單點、路線、中斷或停止中狀態），對 `SimulationStore` 發出與既有「停止模擬」相同的 stop；clear 成功即回到未啟用模擬狀態，clear 失敗時模擬狀態區照常顯示失敗與既有重試入口，Reset 不得將 App 呈現為已恢復真實定位。
   - 模擬處於 busy 狀態（starting、replacing、無失敗的 stopping）時 Reset disabled，與既有控制項一致。

## Non-Goals

- 不提供「把 iPhone 定位設為 Mac 位置」的一鍵操作；改變 iPhone 定位仍必須經過既有的預覽與明確確認流程。
- 不改變既有「停止模擬」按鈕的行為與確認流程；Reset 是其超集合，不取代它。
- 不重置裝置 session 狀態（裝置選擇、tunnel、runtime 安裝狀態）與風險提醒的已確認狀態。
- 不持久化任何設定；本 change 不引入偏好儲存。

## Alternatives Considered

- **Reset 只清 Mac 端工作區、不停模擬**：便宜且無裝置副作用，但與使用者對「回到剛開 App 的樣子」的期待不符（剛開 App 時沒有進行中的模擬）；已與使用者確認採「一起停」。
- **「到 Mac 位置」直接把 Mac 位置設為預覽點**：會把視角操作與定位變更混在一起，踩到「改變 iPhone 位置必須明確確認」的既有契約，放棄。
- **Reset 歸零 generation 計數器**：會讓遲到的舊回應被誤認有效，違反既有 staleness 防護設計，放棄。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `mac-map-initial-location`：新增「使用者指令置中到 Mac 位置」requirement——使用者明確操作時的置中行為、identity 去重與不可用時的 disabled 狀態；並修改既有「初始置中不得覆寫使用者地圖脈絡」requirement，明文授權工作區重置為唯一重新武裝初始置中的操作。
- `location-simulation`：新增「工作區重置」requirement——重置範圍、確認對話框兩種語義、in-flight 要求作廢、與停止模擬的組合行為及 clear 失敗不掩蓋。

## Impact

- Affected specs: `mac-map-initial-location`、`location-simulation`
- Affected code:
  - New: （無）
  - Modified:
    - iPhoneLocationMove/Features/Map/LocationMapModel.swift
    - iPhoneLocationMove/Features/Map/LocationMapView.swift
    - iPhoneLocationMoveTests/LocationMapModelTests.swift
    - iPhoneLocationMoveTests/ContentViewTests.swift
  - Removed: （無）
