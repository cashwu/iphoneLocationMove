## MODIFIED Requirements

### Requirement: 相容的裝置支援環境

系統 SHALL 在連接裝置前驗證 `pymobiledevice3` 的實際能力，至少包含 USB discovery、目前 host policy 所選 tunnel command 的必要 flags，以及 DVT simulate-location `--rsd`，且 MUST NOT 只依版本字串判定相容。macOS 27+ 的 host policy SHALL 要求 `remote start-tunnel --script-mode --native`；macOS 13–26 SHALL 保留 `lockdown start-tunnel --script-mode`。

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

若 macOS 27+ 的 PATH 中 `pymobiledevice3` 可輸出版號，但 `remote start-tunnel --help` 沒有 `--native` 或 `--script-mode`，系統將它視為不相容，而不是沿用。

## ADDED Requirements

### Requirement: macOS native tunnel 相容路徑

在 macOS 27+，系統 SHALL 透過受信任 helper 以 pinned `pymobiledevice3` 的 `remote start-tunnel --native --script-mode` 建立 macOS native tunnel，並 SHALL 將 verified XPC caller 的 effective UID作為 `PYMOBILEDEVICE3_NATIVE_TARGET_UID`，使 tunnel process連到該使用者的 `remotepairingd` domain。系統 MUST 只在取得有效 RSD address 與 port後繼續 DVT preparation，且 MUST NOT 在 native tunnel失敗時靜默退回 classic tunnel。macOS 13–26 MUST 保留既有 classic tunnel policy，避免本修復改變原支援矩陣的 transport contract。

#### Scenario: macOS 27 連接 iOS 27 USB iPhone

- **GIVEN** Mac 為 macOS 27
- **AND** selected USB iPhone 為 iOS 27、已信任、Developer Mode 與 DDI 已就緒
- **WHEN** App 準備 device session
- **THEN** helper SHALL 以 pinned native tunnel取得有效 RSD address 與 port
- **AND** App SHALL 繼續 DVT preparation並在 DVT ready後發布 ready session

#### Scenario: 較早的受支援 macOS 維持既有 transport

- **GIVEN** Mac 為 macOS 13–26
- **WHEN** App 準備 iOS 17+ device session
- **THEN** helper SHALL 使用既有 `lockdown start-tunnel --script-mode --udid <deviceID>` policy
- **AND** helper MUST NOT 設定 `PYMOBILEDEVICE3_NATIVE_TARGET_UID`
- **AND** pinned runtime upgrade MUST NOT 將較早 host 靜默切換到 native command

#### Scenario: helper 連到 verified caller 的 user domain

- **GIVEN** helper 運行於 system launchd domain
- **AND** XPC caller 已通過 code-signature verification
- **WHEN** helper 為該 caller 啟動 native tunnel
- **THEN** tunnel process 的 `PYMOBILEDEVICE3_NATIVE_TARGET_UID` SHALL 等於 verified caller 的 effective UID
- **AND** caller MUST NOT 透過 request指定或覆寫該 UID、command、arguments 或 environment

#### Scenario: 升級時存在舊版 sealed runtime

- **GIVEN** 舊版 helper runtime 已存在於舊 `current` 或其他版本目錄
- **WHEN** 新 helper 第一次建立 tunnel
- **THEN** helper SHALL 安裝並執行目前 pinned version 的獨立 root-owned sealed runtime
- **AND** helper MUST NOT 執行、覆寫或信任舊版 runtime
- **AND** 舊版 runtime 的存在 MUST NOT 使目前 pinned runtime被誤判為遭竄改
- **AND** helper MUST NOT 刪除或修改舊版 runtime 的內容或 metadata

#### Scenario: native tunnel 在 endpoint 前失敗

- **WHEN** native tunnel process 在輸出有效 RSD endpoint 前退出、逾時或無法連到 target user domain
- **THEN** 系統 SHALL 保持 device session non-ready並回傳 tunnel failure
- **AND** helper SHALL 依既有 pending ownership規則停止並回收該 process
- **AND** 系統 MUST NOT fallback 到 classic `lockdown start-tunnel`
