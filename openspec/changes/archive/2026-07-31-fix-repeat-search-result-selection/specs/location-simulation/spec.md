## MODIFIED Requirements

### Requirement: 地圖搜尋、選點與明確確認

系統 SHALL 使用 MapKit 顯示地圖，支援地名／地址搜尋與直接點擊選點。搜尋或點擊只 SHALL 更新 preview marker、地址與座標，MUST NOT 立即改變 iPhone 位置。搜尋結果選取 MAY 以程式化 camera 將地圖移至結果；目前仍顯示的每一筆搜尋結果 SHALL 在每次選取時保持可用，並以新的 `MapSearchGeneration` camera intent 更新 preview 與將地圖移至該結果，即使再次選取相同結果亦同。直接點擊選點 MUST 保留點擊當下的完整 visible region，MUST NOT 因 preview 更新而平移、置中或縮放 camera。

#### Scenario: 搜尋並預覽地點

- **WHEN** 使用者搜尋地名或地址並選擇結果
- **THEN** 系統 SHALL 將地圖移至結果並顯示 preview marker、地址與座標
- **AND** iPhone 定位 MUST 保持不變

#### Scenario: 連續選取目前顯示的不同搜尋結果

- **GIVEN** 搜尋結果清單仍顯示位置 A 與位置 B
- **WHEN** 使用者先選取位置 A，再選取位置 B
- **THEN** 每次選取 SHALL 建立不同的 `MapSearchGeneration` camera intent
- **AND** 最後的 preview marker、地址與座標 SHALL 對應位置 B
- **AND** 地圖 SHALL 移至位置 B
- **AND** iPhone 定位 MUST 保持不變

##### Example: 從「大坑」切換至「大坑里」

- 使用者選取「大坑」→ preview marker 與地圖移至「大坑」座標
- 搜尋結果清單仍顯示時，使用者選取「大坑里」→ 同一個 preview marker 與地圖移至「大坑里」座標

#### Scenario: 再次選取同一筆顯示中的搜尋結果

- **GIVEN** 使用者已選取位置 A，且位置 A 仍顯示於搜尋結果清單
- **AND** 使用者之後手動將 camera 移離位置 A
- **WHEN** 使用者再次選取位置 A
- **THEN** 系統 SHALL 建立新的 `MapSearchGeneration` camera intent
- **AND** 系統 SHALL 將地圖重新移至位置 A
- **AND** 先前位置 A 的已消耗 intent MUST NOT 抑制本次置中

#### Scenario: 重繪前的舊結果 action 不取消較新搜尋

- **GIVEN** 使用者已啟動較新的搜尋，且先前結果的舊 action 在 view 重繪完成前仍可能被觸發
- **WHEN** 該舊 action 對不在目前 `searchResults` 的結果發出選取
- **THEN** 系統 SHALL 拒絕該 stale selection
- **AND** 較新的 MapKit search 與 preview-address lookup MUST NOT 被該舊 action 取消
- **AND** 較新搜尋結果到達後 SHALL 仍可成為 current `searchResults`

#### Scenario: 回到相同搜尋座標仍重新置中

- **GIVEN** 使用者先搜尋位置 A，之後移動 camera 並直接點擊位置 B
- **WHEN** 使用者再次搜尋並選擇位置 A
- **THEN** 系統 SHALL 以新的 `MapSearchGeneration` camera intent 將地圖移至位置 A
- **AND** 先前位置 A 的已消耗 intent MUST NOT 抑制本次置中

#### Scenario: 既有路線不遮蔽後續搜尋置中

- **GIVEN** 地圖已有 route overlay，且該 route identity 的 route fit 已套用
- **WHEN** 使用者搜尋地名或地址並選擇結果
- **THEN** 系統 SHALL 將地圖移至搜尋結果
- **AND** 已消耗的 route identity MUST NOT 因 overlay 仍存在而遮蔽新的搜尋 camera intent

#### Scenario: 新路線優先且搜尋 intent 不延遲重播

- **GIVEN** 新 route identity 與尚未消耗的搜尋 camera intent 在同一次 render 出現
- **WHEN** 系統套用新的 route fit
- **THEN** route fit SHALL 取得本次 camera ownership
- **AND** 同輪搜尋 intent SHALL 被消耗但 MUST NOT 執行 preview center
- **AND** 後續 annotation 或 overlay redraw MUST NOT 延遲重播該搜尋 intent

#### Scenario: 舊搜尋結果晚到

- **GIVEN** 使用者已送出較新的搜尋 query
- **WHEN** 較舊 query 的 MapKit response 較晚到達
- **THEN** 系統 SHALL 以 `MapSearchGeneration` 忽略舊 response
- **AND** current preview MUST 保持對應最新 query

#### Scenario: 直接點擊地圖

- **GIVEN** 使用者已平移或縮放地圖至一個 visible region
- **WHEN** 使用者點擊該 visible region 內的有效地圖座標
- **THEN** 系統 SHALL 遞增 `MapSearchGeneration`、取消可取消的 in-flight search，並更新 preview marker 與座標
- **AND** 點擊前後的 visible region SHALL 完全相同
- **AND** preview 更新與 reverse-geocode 地址更新 MUST NOT 執行 camera 平移、置中、縮放或 route fit
- **AND** 系統 SHALL 等待使用者明確選擇「設定位置」或將點指定為 A／B

##### Example: 放大後連續選點維持相同視野

- 使用者把地圖放大到約 200 公尺可視範圍後點擊位置 A → preview marker 移到 A，visible region 仍為同一個約 200 公尺範圍
- reverse-geocode 回傳 A 的地址 → 地址更新，visible region 不變
- 使用者在同一視野點擊位置 B → preview marker 移到 B，visible region 仍不變

#### Scenario: 點擊地圖後舊搜尋結果晚到

- **GIVEN** search request 尚未完成
- **WHEN** 使用者直接點擊地圖取代 preview，之後舊 search response 到達
- **THEN** 系統 SHALL 忽略舊 response
- **AND** current preview SHALL 保持為使用者點擊的座標
- **AND** 系統 MUST NOT 因忽略舊 response 或更新 preview 地址而改變 camera
