## ADDED Requirements

### Requirement: 工作區重置

系統 SHALL 在地圖控制欄提供「Reset」按鈕，把 Mac 端地圖工作區重置到 App 剛啟動的狀態。按下按鈕後系統 MUST 先顯示確認對話框才執行：顯示確認對話框當下模擬持有清理責任時，警語 MUST 包含 clear 語義句「只有手機回覆 clear 成功後，App 才會顯示已恢復真實定位。」；無清理責任時（含裝置未就緒的未連線模式）SHALL 使用說明會清除搜尋、A/B 端點與路線設定的輕量警語。

確認後系統 SHALL 立即重置 Mac 端工作區：清空搜尋框、搜尋結果、預覽點、A/B 端點、路線預覽與路線狀態、錯誤訊息，步行速度回到預設 4.5 km/h，往返循環回到關閉。所有 in-flight 的 search、reverse geocode 與 directions 要求 MUST 被取消，且其回應 MUST 以 generation 判定為 stale 而不得套用；generation 計數器 MUST NOT 歸零，MUST 以單調遞增方式作廢舊回應。

執行當下模擬持有清理責任時，系統 SHALL 同時發出與既有「停止模擬」相同的停止流程；clear 失敗時系統 MUST NOT 將 App 呈現為已恢復真實定位，MUST 保留既有的失敗顯示與清理重試入口，且 Mac 端工作區重置不因 clear 失敗而回復。模擬處於 busy 狀態（starting、replacing、無失敗的 stopping）時「Reset」按鈕 SHALL 為 disabled。

重置後的地圖鏡頭：Mac 目前位置已取得時 SHALL 置中到 Mac 目前位置；尚未取得時 SHALL 重新武裝初始置中，使後續第一次取得 Mac 位置時依既有初始置中規則置中，等同 App 剛啟動。

#### Scenario: 模擬進行中重置需 clear 語義確認並停止模擬

- **GIVEN** 步行路線模擬正在進行
- **WHEN** 使用者按下「Reset」
- **THEN** 顯示含「只有手機回覆 clear 成功後，App 才會顯示已恢復真實定位。」的確認對話框
- **AND** 使用者確認後，Mac 端工作區立即重置
- **AND** 系統對模擬發出與既有「停止模擬」相同的停止流程

#### Scenario: 無模擬時重置使用輕量確認

- **GIVEN** 模擬未啟用或裝置未就緒
- **WHEN** 使用者按下「Reset」並確認
- **THEN** 確認警語為輕量版本，說明會清除搜尋、A/B 端點與路線設定
- **AND** Mac 端工作區重置，不對裝置發出任何命令

#### Scenario: 重置範圍與預設值

- **GIVEN** 使用者已搜尋地點、設定預覽點與 A/B 端點、建立路線預覽並把速度調為非預設值
- **WHEN** 使用者確認重置
- **THEN** 搜尋框、搜尋結果、預覽點、A/B 端點、路線預覽與路線狀態、錯誤訊息全部清空
- **AND** 步行速度回到 4.5 km/h，往返循環回到關閉

##### Example: 速度與往返循環回到預設

- 重置前：速度 6.0 km/h、往返循環開啟、A/B 已設定且路線可確認
- 確認重置後：速度 4.5 km/h、往返循環關閉、A/B 清空、路線狀態回到未建立

#### Scenario: in-flight 回應在重置後判定 stale

- **GIVEN** 一個 search 要求與一個 directions 要求尚未完成
- **WHEN** 使用者確認重置
- **AND** 之後舊要求的回應才到達
- **THEN** 兩個回應皆被判定 stale 而不套用
- **AND** generation 計數器未歸零，維持單調遞增

#### Scenario: clear 失敗不掩蓋且工作區維持已重置

- **GIVEN** 模擬進行中，使用者確認重置
- **WHEN** 手機端 clear 失敗
- **THEN** 模擬狀態顯示既有的清除失敗訊息與清理重試入口
- **AND** App 不呈現為已恢復真實定位
- **AND** Mac 端工作區維持已重置狀態

#### Scenario: busy 狀態下 Reset disabled

- **WHEN** 模擬處於 starting、replacing 或無失敗的 stopping 狀態
- **THEN** 「Reset」按鈕為 disabled

#### Scenario: 重置後的鏡頭行為

- **WHEN** 使用者確認重置且 Mac 目前位置已取得
- **THEN** 地圖鏡頭置中到 Mac 目前位置
- **WHEN** 使用者確認重置且 Mac 目前位置尚未取得
- **THEN** 後續第一次取得 Mac 位置時，地圖依既有初始置中規則置中
