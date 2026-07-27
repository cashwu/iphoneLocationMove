## ADDED Requirements

### Requirement: 裝置就緒後要求 Mac 目前位置

系統 SHALL 在受支援 iPhone 的新 ready session 建立後，使用 macOS 標準定位授權流程要求一次 Mac 目前位置；系統 MUST NOT 在裝置尚未 ready 時要求位置，也 MUST NOT 要求背景或持續定位。

#### Scenario: 新 ready session 觸發一次定位

- **WHEN** 裝置準備狀態以新的 `DeviceSessionGeneration` 進入 ready
- **THEN** 系統對該 generation 要求一次 Mac 目前位置
- **AND** 同一 generation 的重複 view update 不得再次要求

#### Scenario: 裝置尚未就緒

- **WHEN** 裝置狀態不是 ready
- **THEN** 系統不得要求 Mac 目前位置

#### Scenario: 重新連線建立新 generation

- **WHEN** 裝置重新連線並以新的 `DeviceSessionGeneration` 進入 ready
- **THEN** 系統取消並完成先前仍在等待的定位要求
- **AND** 系統 MAY 對新 generation 再要求一次 Mac 目前位置以更新 marker
- **AND** 先前 generation 的 success 或 failure 回應 MUST 被忽略

#### Scenario: 同一 generation 重開主視窗

- **WHEN** setup store 仍維持同一個 ready `DeviceSessionGeneration`
- **AND** 使用者關閉後重開主視窗
- **THEN** 系統重用 app-lifetime coordinator 的 cached state
- **AND** 系統不得對該 generation 再次要求 Mac 位置

### Requirement: 顯示 Mac 位置且不改變 iPhone 模擬狀態

系統 SHALL 將成功取得的座標顯示為獨立的「Mac 目前位置」marker，並 MUST NOT 將該座標自動設為預覽、A、B、步行路線或 iPhone 模擬位置。

#### Scenario: 首次成功取得位置

- **WHEN** 目前 ready generation 成功取得有效 Mac 座標
- **THEN** 地圖顯示 title 為「Mac 目前位置」的 marker
- **AND** `preview`、`endpointA`、`endpointB` 與 route state 維持不變
- **AND** 系統不得呼叫 `DeviceLocationClient.setLocation`

#### Scenario: 更新 marker

- **WHEN** 新 ready generation 取得較新的有效 Mac 座標
- **THEN** 系統更新既有 Mac marker
- **AND** 地圖上不得累積多個 Mac 位置 marker

### Requirement: 初始置中不得覆寫使用者地圖脈絡

系統 SHALL 只在使用者尚未搜尋、選點、設定端點、要求路線、平移或縮放地圖時，以首次 Mac 位置自動置中一次。晚到的非同步位置結果 MAY 更新 marker，但 MUST NOT 覆寫較新的使用者視角或選擇狀態。

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
- **AND** 新 ready generation 取得 Mac 位置
- **THEN** 系統只更新 marker
- **AND** 系統不得重新取得 camera ownership

#### Scenario: route 存在時 marker 晚到

- **WHEN** 地圖已有 route 且使用者在 route fit 後手動移動 camera
- **AND** Mac 位置結果稍後更新 annotation
- **THEN** 系統不得重播既有 route 的 `setVisibleMapRect` effect
- **AND** 只有新的 route request identity MAY 再次取得 route camera ownership

### Requirement: 定位授權與失敗安全降級

系統 SHALL 對定位拒絕、限制、服務停用與定位失敗提供非阻塞的使用者提示，並 MUST NOT 使用預設城市、IP 推測或其他 fallback 座標冒充 Mac 目前位置。

#### Scenario: 首次授權

- **WHEN** Mac 定位 authorization 為 `notDetermined`
- **THEN** 系統使用 `When In Use` 標準授權 prompt 說明地圖初始定位用途
- **AND** 授權成功後只要求一次位置

#### Scenario: 權限拒絕或受限制

- **WHEN** 定位 authorization 為 `denied` 或 `restricted`
- **THEN** 地圖控制區顯示可理解且非阻塞的權限提示
- **AND** 搜尋、選點與 iPhone 模擬控制仍可使用
- **AND** 系統不得建立假的目前位置 marker

#### Scenario: 服務停用或定位失敗

- **WHEN** macOS 定位服務停用或一次性定位要求失敗
- **THEN** 地圖控制區顯示目前無法取得 Mac 位置的提示
- **AND** 既有地圖與裝置 session 繼續運作
- **AND** 系統不得套用 fallback 座標
