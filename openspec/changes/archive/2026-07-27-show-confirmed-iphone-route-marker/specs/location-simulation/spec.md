## ADDED Requirements

### Requirement: 已確認的 iPhone 路線位置標記

系統 SHALL 在 route simulation 已取得 iPhone 成功確認的座標後，於地圖顯示可與 A、B、preview及 Mac 目前位置清楚區分的「iPhone 模擬位置」marker。marker 的位置 MUST 只來自route已確認truth：route state使用`RouteSimulationSnapshot.confirmedCoordinate`，stopping state使用同一`RouteSession.confirmedCoordinate`；系統 MUST NOT 顯示pending、預測或尚未被device mutation確認的座標。

#### Scenario: 首次成功定位後顯示 marker

- **WHEN** route 的第一筆 device mutation成功並 publish `confirmedCoordinate`
- **THEN** 地圖 SHALL 在該 coordinate顯示「iPhone 模擬位置」marker
- **AND** marker SHALL 使用與 A、B、preview及「Mac 目前位置」不同的視覺樣式

#### Scenario: 後續成功更新原地移動 marker

- **WHEN** 同一 route session publish新的 `confirmedCoordinate`
- **THEN** 地圖 SHALL 更新既有 iPhone marker的 coordinate
- **AND** 系統 MUST NOT 因該更新移除重建其他 annotations

#### Scenario: pending 或 recovery 期間不提前移動

- **WHEN** 新 route mutation仍 pending或 transport recovery尚未完成
- **THEN** marker SHALL 保持在最後一個 confirmed coordinate
- **AND** 地圖 MUST NOT 顯示 pending request coordinate或依 elapsed time推算的位置

#### Scenario: 暫停與完成時保留已確認位置

- **WHEN** route進入 paused或single-trip completed且 position仍為已知
- **THEN** marker SHALL 保留在最後 confirmed coordinate

#### Scenario: 停止與 clear failure 保留已確認位置

- **WHEN** position knowledge仍可信的route進入stopping且clear仍pending或clear失敗
- **THEN** marker SHALL 保留在最後 confirmed coordinate
- **AND** UI MUST NOT 暗示裝置已恢復真實定位

#### Scenario: 位置不確定或 clear 成功時移除 marker

- **WHEN** route進入帶有`positionKnowledge == unknown`的interrupted state、clear成功後的idle、point mode或replacement尚未確認新route coordinate
- **THEN** 地圖 SHALL 移除 iPhone route marker
- **AND** 系統 MUST NOT 以最後已知位置假裝目前 iPhone 位置仍可信

#### Scenario: Position unknown 後停止仍不重新顯示 marker

- **WHEN** 已有confirmed coordinate的route因`positionKnowledge == unknown`移除marker
- **AND** 使用者隨後停止route，且clear仍pending或clear失敗
- **THEN** marker SHALL 保持移除
- **AND** stopping state MUST NOT 從保留的route session重新顯示已不可信座標

#### Scenario: marker 更新不影響 camera ownership

- **WHEN** iPhone marker新增、移動或移除
- **THEN** 地圖 MUST NOT 因 marker變化重新執行 route fit、preview center或 Mac initial center
- **AND** 未改變的route overlay SHALL 保持同一identity，不得因marker-only更新而移除重建
- **AND** marker變化 MUST NOT 被分類為使用者手動 camera interaction
