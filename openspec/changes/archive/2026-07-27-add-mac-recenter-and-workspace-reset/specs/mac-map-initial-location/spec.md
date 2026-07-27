## ADDED Requirements

### Requirement: 使用者指令置中到 Mac 位置

系統 SHALL 在地圖控制欄提供「到 Mac 位置」按鈕；按下後 SHALL 只把地圖鏡頭置中到 Mac 目前位置，MUST NOT 改變預覽點、A/B 端點或任何 iPhone 模擬定位狀態。置中 MUST 以可消耗 identity 套用一次：每次按下產生一個新的 identity，annotation 或 overlay redraw MUST NOT 重播已套用的置中。程式化置中 MUST NOT 被記錄為使用者手動鏡頭操作，但按下按鈕本身 SHALL 記錄使用者地圖脈絡並清除尚未消耗的初始置中 intent。Mac 目前位置尚未取得時，按鈕 SHALL 為 disabled。

#### Scenario: 按下按鈕置中且不影響工作區與模擬

- **GIVEN** Mac 目前位置已取得
- **AND** 使用者已設定預覽點與 A/B 端點
- **WHEN** 使用者按下「到 Mac 位置」
- **THEN** 地圖鏡頭置中到 Mac 目前位置
- **AND** 預覽點、A/B 端點、路線預覽與 iPhone 模擬狀態全部不變

#### Scenario: 置中以 identity 去重且 redraw 不重播

- **WHEN** 使用者按下「到 Mac 位置」一次
- **AND** 之後地圖因 annotation 更新而重新繪製
- **THEN** 置中鏡頭操作只執行一次
- **AND** 使用者再按一次按鈕時，以新的 identity 再置中一次

##### Example: 兩次按下產生兩次置中、redraw 零次重播

- 按下第 1 次 → identity 1 置中執行 1 次
- 期間發生 3 次 annotation redraw → 置中不再執行
- 按下第 2 次 → identity 2 置中執行 1 次；總計恰為 2 次

#### Scenario: 置中不被誤判為手動操作且取代初始置中

- **GIVEN** 初始置中 intent 尚未被消耗
- **WHEN** 使用者按下「到 Mac 位置」
- **THEN** 尚未消耗的初始置中 intent 被清除，僅執行本次置中
- **AND** 本次程式化鏡頭移動不被記錄為使用者手動鏡頭操作

#### Scenario: Mac 位置不可用時按鈕 disabled

- **WHEN** Mac 目前位置尚未取得（授權未給、查詢中或查詢失敗）
- **THEN** 「到 Mac 位置」按鈕為 disabled
- **AND** 不產生任何鏡頭操作

## MODIFIED Requirements

### Requirement: 初始置中不得覆寫使用者地圖脈絡

系統 SHALL 只在使用者尚未搜尋、選點、設定端點、要求路線、平移或縮放地圖時，以首次 Mac 位置自動置中一次。晚到的非同步位置結果 MAY 更新 marker，但 MUST NOT 覆寫較新的使用者視角或選擇狀態。工作區重置 SHALL 為唯一重新武裝初始置中的操作：重置當下 Mac 位置尚未取得時，系統 SHALL 視同 App 剛啟動，後續首次有效 Mac 位置 MAY 重新自動置中一次。

#### Scenario: 尚無使用者地圖脈絡

- **WHEN** 首次有效 Mac 位置抵達且使用者尚未操作地圖
- **THEN** 地圖以該座標自動置中一次
- **AND** 後續 SwiftUI update 不得重複套用相同 initial-center intent

#### Scenario: 搜尋或選點早於定位結果

- **WHEN** 使用者已搜尋、選點、設定 A／B 或要求路線
- **AND** Mac 位置結果稍後抵達
- **THEN** 系統更新 Mac marker
- **AND** 系統維持使用者目前的 preview、端點、route 與 camera 脈絡

#### Scenario: 手動操作地圖早於定位結果

- **WHEN** 使用者已平移或縮放地圖
- **AND** Mac 位置結果稍後抵達
- **THEN** 系統更新 Mac marker
- **AND** 系統不得將 camera 移回 Mac 位置

#### Scenario: 重新連線更新位置

- **WHEN** initial-center intent 已經套用或已被使用者操作撤銷
- **AND** 其後未發生重新武裝初始置中的工作區重置（未發生重置，或重置當下 Mac 位置已取得因而未重新武裝）
- **AND** 新 ready generation 取得 Mac 位置
- **THEN** 系統只更新 marker
- **AND** 系統不得重新取得 camera ownership

#### Scenario: route 存在時 marker 晚到

- **WHEN** 地圖已有 route 且使用者在 route fit 後手動移動 camera
- **AND** Mac 位置結果稍後更新 annotation
- **THEN** 系統不得重播既有 route 的 `setVisibleMapRect` effect
- **AND** 只有新的 route request identity MAY 再次取得 route camera ownership

#### Scenario: 工作區重置後重新武裝初始置中

- **GIVEN** initial-center intent 已經套用或已被使用者操作撤銷
- **WHEN** 使用者確認工作區重置且重置當下 Mac 位置尚未取得
- **AND** 之後首次有效 Mac 位置抵達且使用者尚未再操作地圖
- **THEN** 地圖以該座標重新自動置中一次
- **AND** 後續 SwiftUI update 不得重複套用相同 initial-center intent
