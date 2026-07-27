## ADDED Requirements

### Requirement: 地圖控制欄按鈕穩定布局

系統 SHALL 讓固定寬度地圖控制欄中的所有可見按鈕使用一致且可預期的布局：單獨成列的主要操作 SHALL 共用左側 baseline 並保持在控制欄內容邊界內；同列的多個操作 SHALL 靠左排列、互不重疊且具有一致間距。按鈕標題長度、disabled 狀態、裝置連線狀態、模擬 busy 狀態、路線 phase 或清理失敗狀態的變化 MUST NOT 造成按鈕重疊、越出側欄、覆蓋狀態文字或改變其他功能群組的位置規則。

DEBUG 測試 action marker MUST NOT 產生可見標題、邊框或 focus ring，MUST NOT 取得可見布局尺寸，且 MUST NOT 攔截使用者 hit testing。移除 marker 的布局影響 MUST NOT 改變 production 按鈕的 action、role、disabled 條件、accessibility identifier 或必要確認流程。

#### Scenario: 初始側欄所有按鈕對齊且不重疊

- **GIVEN** 地圖控制欄以 320 pt 欄寬顯示，且尚未執行「到 Mac 位置」或「Reset」
- **WHEN** 系統完成初始 layout
- **THEN** 「到 Mac 位置」、`Reset`、搜尋、清除、路線與當前 iPhone 定位區中所有可見按鈕 SHALL 位於側欄內容邊界內且互不重疊
- **AND** 單獨成列的主要操作 SHALL 共用左側 baseline
- **AND** 同列操作 SHALL 靠左排列並保持一致間距

#### Scenario: 裝置與模擬狀態切換不造成跑版

- **GIVEN** 地圖控制欄已顯示
- **WHEN** 定位控制以 disconnected 狀態初始化，或同一 rendered hierarchy 觀察的 `SimulationStore` 從 idle connected 切換到 busy、route running、route paused 或 stopping failure
- **THEN** 當前狀態下新增、移除或 disabled 的按鈕 SHALL 依相同 row 與群組規則布局
- **AND** 任一按鈕 MUST NOT 覆蓋速度、模擬狀態、錯誤或裝置就緒文字
- **AND** 不需要執行按鈕 action 才能得到正確布局

#### Scenario: DEBUG marker 不出現在可見布局

- **GIVEN** App 以 DEBUG 組態顯示地圖控制欄
- **WHEN** hosting view 完成 layout 或任一被觀察狀態更新
- **THEN** 每個 `TestingActionMarker` SHALL 保持零寬、零高、透明且沒有 focus ring，並拒絕成為 first responder
- **AND** marker MUST NOT 攔截使用者點擊或鍵盤 focus
- **AND** 測試仍 SHALL 能透過既有 identifier 觸發對應 seam，以驗證 Reset 先顯示確認再執行

#### Scenario: 布局修正不改變按鈕行為

- **WHEN** 使用者操作「到 Mac 位置」、`Reset`、搜尋、清除、A/B、路線或 iPhone 定位區按鈕
- **THEN** 每個按鈕 SHALL 保留修正前的 action、role、disabled 條件與 accessibility identifier
- **AND** 「到 Mac 位置」與 `Reset` 的既有 camera、workspace reset、clear failure 與 confirmation contract MUST 保持不變
