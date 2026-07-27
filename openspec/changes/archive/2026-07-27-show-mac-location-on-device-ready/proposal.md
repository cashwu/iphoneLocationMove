## Summary

在受支援的 iPhone 完成 USB 準備後，使用 macOS Core Location 取得 Mac 的一次性目前位置，於地圖顯示「Mac 目前位置」標記並在使用者尚未建立地圖脈絡時自動置中。此功能只改變地圖初始視角，不會自動設定或變更 iPhone 的模擬定位。

## Motivation

目前裝置就緒後，地圖維持 MapKit 預設視角，使用者通常要先搜尋或拖曳到所在地區，才能開始選擇單點或步行端點。直接讀取 iPhone 真實 GPS 需要額外 iOS companion app、定位授權與跨裝置通訊；使用 Mac 目前位置能以較小、可維護且符合公開 API 的方式提供實用的初始地圖脈絡。

## Proposed Solution

- 由 app-lifetime 的 Mac 定位 coordinator 觀察每次 `DeviceSetupState.ready` generation，透過可測試的一次性 Mac 定位 client 請求目前座標；重建或重開視窗不會對同一 generation 重複要求。
- 首次需要定位時使用標準 macOS 定位授權流程，並在授權拒絕、限制、定位服務停用或定位失敗時提供非阻塞提示。
- 成功後在地圖加入獨立的「Mac 目前位置」標記；該標記不成為預覽、A／B 端點或 iPhone 模擬座標。
- 只有在使用者尚未搜尋、選點、建立端點、操作地圖或取得路線時，才以 Mac 位置自動置中一次。
- ready generation 變更時先取消並完成舊要求，再啟動新要求；非同步定位結果不得覆寫較新的 session 或使用者地圖脈絡。
- 所有 programmatic camera effect 都以一次性 identity 套用；重新連線或 annotation-only 更新可更新標記，但不得重播既有 preview／route camera effect。

## Non-Goals

- 不讀取或宣稱顯示 iPhone 的真實 GPS 位置。
- 不新增 iPhone companion app、CloudKit、區域網路或其他跨裝置位置傳輸。
- 不在取得 Mac 位置後自動呼叫 `setLocation`，也不自動建立 A／B 或步行路線。
- 不持續追蹤 Mac 位置，不要求背景定位或 `Always` 授權。
- 不以 IP 位址、預設城市或上次模擬座標冒充目前位置。

## Alternatives Considered

- 新增 iPhone companion app：能取得 iPhone GPS，但需要額外安裝、簽章、權限與通訊流程，超出本次以小範圍改善初始地圖體驗的目標。
- 顯示上次模擬座標：實作較小，但該座標可能過期且不能代表目前實體位置。
- 無條件以 Mac 位置重設地圖：會讓較晚完成的定位要求覆寫使用者搜尋、選點或手動移動地圖，因此不採用。

## Capabilities

### New Capabilities

- `mac-map-initial-location`：裝置就緒後取得 Mac 一次性位置、顯示明確標記，並以不覆寫使用者地圖脈絡的方式設定初始視角。

### Modified Capabilities

- (none)

## Impact

- Affected specs:
  - New: `openspec/changes/show-mac-location-on-device-ready/specs/mac-map-initial-location/spec.md`
- Affected code:
  - New:
    - `iPhoneLocationMove/Features/Map/MacLocationClient.swift`
    - `iPhoneLocationMoveTests/MacLocationClientTests.swift`
  - Modified:
    - `iPhoneLocationMove/Info.plist`
    - `iPhoneLocationMove/ContentView.swift`
    - `iPhoneLocationMove/App/iPhoneLocationMoveApp.swift`
    - `iPhoneLocationMove/Features/Map/LocationMapModel.swift`
    - `iPhoneLocationMove/Features/Map/LocationMapView.swift`
    - `iPhoneLocationMoveTests/AppShellTests.swift`
    - `iPhoneLocationMoveTests/LocationMapModelTests.swift`
    - `iPhoneLocationMove.xcodeproj/project.pbxproj`
  - Removed:
    - (none)
