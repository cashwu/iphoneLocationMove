## ADDED Requirements

### Requirement: 相容的裝置支援環境

系統 SHALL 在連接裝置前驗證 `pymobiledevice3` 的實際能力，至少包含 USB discovery、`lockdown start-tunnel --script-mode` 與 DVT simulate-location `--rsd`，且 MUST NOT 只依版本字串判定相容。

#### Scenario: 沿用相容的既有安裝

- **GIVEN** Mac 上已有通過全部 capability probes 的 `pymobiledevice3`
- **WHEN** App 準備裝置支援環境
- **THEN** 系統 SHALL 沿用該安裝
- **AND** 系統 MUST NOT 建立新的 user venv

#### Scenario: 一鍵建立 App 專用環境

- **GIVEN** 沒有相容的既有 `pymobiledevice3`
- **AND** Mac 上有 Python `>=3.9`
- **WHEN** 使用者選擇「安裝裝置支援」
- **THEN** 系統 SHALL 在 App 專用 Application Support 目錄建立 venv
- **AND** 系統 SHALL 安裝 lockfile 指定的版本並顯示進度
- **AND** 系統 MUST NOT 修改 global Python 或 Homebrew

#### Scenario: 沒有相容 Python

- **GIVEN** 沒有相容的既有 `pymobiledevice3`
- **AND** Mac 上沒有 Python `>=3.9`
- **WHEN** App 檢查裝置支援環境
- **THEN** 系統 SHALL 顯示可執行的 Python 安裝指引
- **AND** 系統 MUST NOT 宣稱可開始裝置連線

#### Scenario: 安裝取消或失敗

- **WHEN** 使用者取消 App 專用環境安裝，或安裝程序失敗
- **THEN** 系統 SHALL 保留可重試的未就緒狀態
- **AND** 系統 SHALL 顯示可操作的錯誤資訊
- **AND** 系統 MUST NOT 使用不完整的 venv

#### Scenario: privileged tunnel runtime 無安全 interpreter

- **GIVEN** unprivileged DVT 環境可用
- **AND** 系統找不到 root-owned、不可由一般使用者修改且版本 `>=3.9` 的 Python interpreter
- **WHEN** App 準備 privileged tunnel runtime
- **THEN** 系統 SHALL 顯示 tunnel prerequisite 指引
- **AND** root helper MUST NOT 執行 user-writable Python

##### Example: 版本存在但能力不足

若 PATH 中的 `pymobiledevice3` 可輸出版號，但 `lockdown start-tunnel --help` 沒有 `--script-mode`，系統將它視為不相容，而不是沿用。

### Requirement: USB 裝置偵測與選擇

系統 SHALL 只列出透過 USB 可用的 iPhone，且同一時間 SHALL 最多選擇一台 active device。

#### Scenario: 沒有 USB iPhone

- **WHEN** 系統找不到 USB iPhone
- **THEN** 系統 SHALL 顯示未連線狀態與解鎖、資料線及信任提示
- **AND** 定位操作 SHALL 保持停用

#### Scenario: 偵測到一台裝置

- **WHEN** 系統只偵測到一台可識別的 USB iPhone
- **THEN** 系統 SHALL 選擇該裝置並顯示裝置名稱與 iOS 版本

#### Scenario: 偵測到多台裝置

- **WHEN** 系統同時偵測到多台 USB iPhone
- **THEN** 系統 SHALL 要求使用者選擇其中一台
- **AND** 系統 MUST NOT 同時對多台裝置建立 active simulation session

#### Scenario: 偵測到 iOS 17 以下裝置

- **WHEN** 系統偵測到 iOS 17 以下的 USB iPhone
- **THEN** 系統 SHALL 顯示裝置名稱、版本與 unsupported 狀態
- **AND** 系統 MUST NOT 對該裝置開始 tunnel 或 DVT preparation

#### Scenario: active 狀態要求切換裝置

- **GIVEN** selected device 已 ready、active 或 cleanup-pending
- **WHEN** 使用者選擇另一台 USB iPhone
- **THEN** 系統 SHALL 先對舊 UDID 依序停止 producer、clear、shutdown helper 與 stop tunnel lease
- **AND** 系統 SHALL 只在舊裝置 cleanup 成功後 commit 新 selection

#### Scenario: 切換裝置時舊裝置 clear 失敗

- **WHEN** device switch transaction 無法確認舊裝置 clear success
- **THEN** 系統 SHALL 保留舊 UDID 的 cleanup ownership 與重試動作
- **AND** 系統 MUST NOT commit 新 selection

### Requirement: 裝置 prerequisite 準備順序

系統 SHALL 依序完成 runtime probe、USB device selection、pairing／trust、Developer Mode、DDI、tunnel 與 DVT helper readiness；任一步失敗時 MUST 停止後續準備並顯示該階段的修復資訊。

#### Scenario: 尚未信任 Mac

- **WHEN** selected iPhone 尚未與 Mac 配對或信任
- **THEN** 系統 SHALL 要求使用者解鎖 iPhone 並完成信任
- **AND** 系統 MUST NOT 嘗試開始定位 session

#### Scenario: Developer Mode 未開啟

- **WHEN** selected iPhone 的 Developer Mode 未開啟
- **THEN** 系統 SHALL 顯示 iOS 設定路徑與重新啟動需求
- **AND** 系統 MUST NOT 跳過此檢查

#### Scenario: DDI 無法準備

- **WHEN** DDI mount 未成功且不是 already-mounted 結果
- **THEN** 系統 SHALL 顯示 DDI 準備失敗
- **AND** 系統 MUST NOT 把 device session 標記為 ready

### Requirement: 最小 privileged tunnel 邊界

系統 SHALL 透過受授權的 privileged helper 建立 iOS 17+ tunnel。該 helper MUST 只接受 typed `startTunnel(deviceID, idempotencyKey)`／`stopTunnel(leaseID)`／`status(leaseID)`／`reconcile()` request，MUST NOT 接受任意 shell command、argument list、interpreter path、package path、manifest path 或 output path，且 SHALL 只執行經 App code signature 與 signed-helper embedded digest trust anchor 驗證、原子安裝並在每次啟動前驗證的 root-owned pinned tunnel runtime。

#### Scenario: 使用者核准 tunnel helper

- **WHEN** 使用者核准 privileged helper 且 selected device prerequisites 已完成
- **THEN** helper SHALL 為該 device 建立 tunnel
- **AND** 系統 SHALL 只在收到有效 RSD address 與 port 後進入 DVT preparation

#### Scenario: 使用者拒絕管理員授權

- **WHEN** 使用者拒絕 privileged helper 的安裝或啟動授權
- **THEN** 系統 SHALL 回到可重試的授權需求狀態
- **AND** 系統 MUST NOT 顯示 tunnel ready

#### Scenario: 非法 privileged request

- **WHEN** helper 收到未授權 caller、無效 device ID、未知 tunnel ID 或 contract 外的 request
- **THEN** helper SHALL 拒絕 request 並回傳結構化錯誤
- **AND** helper MUST NOT 啟動額外 process

#### Scenario: 安裝 privileged runtime payload

- **WHEN** 使用者授權安裝 privileged tunnel runtime
- **THEN** helper SHALL 從 XPC audit token 解析 caller code URL，並驗證 App designated requirement、Team ID 與完整 code signature
- **AND** helper SHALL 只讀取通過 code-signature 驗證且符合 helper executable 內嵌 digest table 的 offline payload
- **AND** helper SHALL 拒絕 symlink、digest mismatch、非 root owner 或群組／全域可寫檔案
- **AND** helper SHALL 經 root-owned temporary directory 驗證後 atomic publish
- **AND** root process MUST NOT 執行網路 `pip` 或 user-writable interpreter／package／manifest／staging payload

#### Scenario: payload 與外部 manifest 同時遭替換

- **WHEN** caller bundle 中的 payload 與其外部 manifest 同時遭替換、重新 ad-hoc signing，或 Team ID／designated requirement 不符
- **THEN** helper SHALL 以自身 executable 內嵌的 trust anchor 與 code-signature requirement fail closed
- **AND** helper MUST NOT 安裝 runtime 或啟動 tunnel

#### Scenario: tunnel runtime 遭竄改

- **WHEN** 每次 start 前的 owner、mode、symlink 或 digest 驗證失敗
- **THEN** helper SHALL fail closed 並回傳 runtime-integrity error
- **AND** helper MUST NOT 啟動 tunnel process

#### Scenario: 重複開始同一 tunnel

- **GIVEN** 同一 signed caller 與 device 已有 active `TunnelLeaseID`
- **WHEN** caller 使用相同 idempotency key 再次 start
- **THEN** helper SHALL 回傳既有 lease 與 endpoint
- **AND** helper MUST NOT 啟動第二個 tunnel process

#### Scenario: caller 消失或 App crash

- **WHEN** owning XPC connection invalidated、caller process 結束或 App crash
- **THEN** helper SHALL 回收該 caller 擁有的 tunnel lease 與 root process

#### Scenario: App 啟動時 reconcile

- **WHEN** App 建立新的 signed XPC session
- **THEN** 系統 SHALL 呼叫 reconcile 並清理不屬於 current caller session 的遺留 lease

### Requirement: 序列化且可關聯的裝置命令

系統 SHALL 序列化 mutating device command，並以 request ID、`SimulationSessionID` 與 `DeviceSessionGeneration` 將結果關聯至 current session。舊 session 或舊 generation 的結果 MUST NOT 改寫 current state。

#### Scenario: 新 session 取代舊 session

- **GIVEN** 舊模擬 session 仍有 pending completion
- **WHEN** 使用者確認開始新的模擬 session
- **THEN** 系統 SHALL 停止舊 producer 並序列化 mode replacement
- **AND** 舊 `SimulationSessionID` 的 completion MUST NOT 改寫新 session 狀態

#### Scenario: 重連後收到舊 callback

- **GIVEN** USB 重連已建立新的 `DeviceSessionGeneration`
- **WHEN** 舊 tunnel 或 helper callback 到達
- **THEN** 系統 SHALL 忽略該 callback
- **AND** current device session SHALL 保持不變

#### Scenario: route update 仍在執行時要求 clear

- **GIVEN** current route update request 尚未完成
- **WHEN** 使用者暫停、停止、切換模式或裝置 session 開始 cleanup
- **THEN** 系統 SHALL 建立 command barrier 或使舊 update epoch 失效
- **AND** clear 後 MUST NOT 再送出或套用舊座標

### Requirement: USB 中斷與安全重連

系統 SHALL 在 USB 中斷時停止位置 producer 並顯示 `interrupted(positionUnknown)`，其中 `positionUnknown` 是 `interrupted` 的 position knowledge payload 而非獨立 state；系統 MUST NOT 自動恢復舊模擬。相同裝置重新連線後 SHALL 建立新 generation，重新準備 tunnel／DVT，並在進入 ready 前成功執行 clear。

#### Scenario: 執行途中拔除 USB

- **WHEN** active point 或 route session 執行期間 USB 中斷
- **THEN** 系統 SHALL 停止送出新的位置更新
- **AND** UI SHALL 顯示無法保證裝置端已 clear 的 `interrupted(positionUnknown)` 狀態

#### Scenario: 同一裝置重新連線

- **GIVEN** device session 因 USB 中斷進入 `interrupted(positionUnknown)`
- **WHEN** 同一台 iPhone 重新以 USB 連線且 prerequisites 完成
- **THEN** 系統 SHALL 建立新 generation 並重新建立 tunnel／DVT session
- **AND** 系統 SHALL 在 clear success 後才進入 ready
- **AND** 系統 MUST NOT 自動繼續舊路線

#### Scenario: 重連後 clear 失敗

- **WHEN** 重新連線後無法確認 clear success
- **THEN** 系統 SHALL 保持非 ready 狀態並提供重試
- **AND** 系統 MUST NOT 宣稱手機已恢復真實定位

### Requirement: App 結束時清理裝置 session

關閉主視窗 MAY 讓 active simulation 繼續，但真正退出 App 時系統 SHALL 對 active simulation 要求確認，並依序停止位置 producer、clear、shutdown DVT helper 與 stop tunnel。

#### Scenario: 關閉主視窗

- **GIVEN** active simulation 正在執行
- **WHEN** 使用者只關閉主視窗
- **THEN** App MAY 留在背景並繼續目前 session
- **AND** 系統 SHALL 提供重新開啟控制視窗的方法

#### Scenario: 沒有 active simulation 但 device session ready 時退出

- **GIVEN** 沒有 active simulation
- **AND** DVT helper 或 tunnel lease 仍 ready
- **WHEN** 使用者退出 App
- **THEN** 系統 SHALL shutdown DVT helper、stop tunnel lease 並執行 reconcile

#### Scenario: 確認退出

- **GIVEN** active simulation 正在執行
- **WHEN** 使用者選擇退出並確認停止
- **THEN** 系統 SHALL 先停止任何 route producer
- **AND** 系統 SHALL 嘗試 clear location、shutdown DVT helper 與 stop tunnel
- **AND** 只有收到 clear success 時系統 MAY 顯示已恢復真實定位

#### Scenario: 退出清理失敗

- **WHEN** clear 或 stop tunnel 失敗
- **THEN** 系統 SHALL 顯示具體失敗與重試選項
- **AND** 系統 SHALL 允許使用者明確選擇強制退出
- **AND** 系統 MUST NOT 把強制退出描述為已安全清除
