## MODIFIED Requirements

### Requirement: 相容的裝置支援環境

系統 SHALL 在連接裝置前驗證 `pymobiledevice3` 的實際能力，至少包含 USB discovery、`lockdown start-tunnel` 的 `--script-mode`，以及 DVT simulate-location `--rsd`，且 MUST NOT 只依版本字串判定相容。所有受支援 macOS SHALL 使用同一組 capability probes，MUST NOT 依 host macOS 版本改要求 `remote start-tunnel` 或 `--native`。

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

#### Scenario: 只具備 native tunnel 能力的安裝不相容

- **GIVEN** Mac 為 macOS 27 或更新版本
- **AND** 既有 `pymobiledevice3` 的 `remote start-tunnel --help` 含 `--native`
- **AND** 其 `lockdown start-tunnel --help` 未通過 exit code 0 且含 `--script-mode` 的檢查
- **WHEN** App 準備裝置支援環境
- **THEN** 系統 MUST NOT 將該安裝視為 ready

##### Example: 版本存在但能力不足

若 PATH 中 `pymobiledevice3` 可輸出版號，但 `lockdown start-tunnel --help` 沒有 `--script-mode`，系統將它視為不相容，而不是沿用；此判定在 macOS 13–26 與 macOS 27+ 相同。

## REMOVED Requirements

### Requirement: macOS native tunnel 相容路徑

**Reason**: iOS 27.2 在 native tunnel 上拒絕所有 service port 連線（measured 2026-10-27，macOS 27.2 + iOS 27.2），上游 `pymobiledevice3` 亦已將 native 降為 opt-in；helper 改為所有 host 使用 classic lockdown tunnel。

**Migration**: 由新增的「classic lockdown USB tunnel 路徑」取代；helper 不再設定 `PYMOBILEDEVICE3_NATIVE_TARGET_UID`，既有 pinned runtime 與 legacy runtime 保留規則移入新 requirement。

#### Scenario: helper 不再啟動 native tunnel

- **GIVEN** Mac 為 macOS 27 或更新版本
- **WHEN** helper 為 verified caller 啟動 tunnel
- **THEN** helper MUST NOT 執行 `remote start-tunnel --native`
- **AND** helper MUST NOT 設定 `PYMOBILEDEVICE3_NATIVE_TARGET_UID`

## ADDED Requirements

### Requirement: classic lockdown USB tunnel 路徑

在所有受支援 macOS，系統 SHALL 透過受信任 helper 以 pinned `pymobiledevice3` 執行固定的 `lockdown start-tunnel --script-mode --udid <deviceID>` 建立 USB tunnel，MUST NOT 執行 `remote start-tunnel` 或 `--native`，且 MUST NOT 設定 `PYMOBILEDEVICE3_NATIVE_TARGET_UID`。系統 MUST 只在取得有效 RSD address 與 port 後繼續 DVT preparation，且 MUST NOT 在 tunnel 失敗時切換到其他 transport。

#### Scenario: macOS 27.2 連接 iOS 27.2 USB iPhone

- **GIVEN** Mac 為 macOS 27.2
- **AND** selected USB iPhone 為 iOS 27.2、已信任、Developer Mode 與 DDI 已就緒
- **WHEN** App 準備 device session
- **THEN** helper SHALL 以 `lockdown start-tunnel --script-mode --udid <deviceID>` 取得有效 RSD address 與 port
- **AND** App SHALL 繼續 DVT preparation 並在 DVT ready 後發布 ready session

#### Scenario: 所有受支援 macOS 使用相同 tunnel command

- **GIVEN** Mac 為 macOS 13–26 或 macOS 27+
- **WHEN** helper 為 verified caller 啟動 tunnel
- **THEN** tunnel process arguments SHALL 等於 `lockdown start-tunnel --script-mode --udid <validated-device-id>`
- **AND** tunnel process environment MUST NOT 含 `PYMOBILEDEVICE3_NATIVE_TARGET_UID` 或 `SUDO_UID`
- **AND** caller MUST NOT 透過 request 指定或覆寫 command、arguments 或 environment

#### Scenario: 升級時存在舊版 sealed runtime

- **GIVEN** 舊版 helper runtime 已存在於舊 `current` 或其他版本目錄
- **WHEN** 新 helper 第一次建立 tunnel
- **THEN** helper SHALL 安裝並執行目前 pinned version 的獨立 root-owned sealed runtime
- **AND** helper MUST NOT 執行、覆寫或信任舊版 runtime
- **AND** 舊版 runtime 的存在 MUST NOT 使目前 pinned runtime 被誤判為遭竄改
- **AND** helper MUST NOT 刪除或修改舊版 runtime 的內容或 metadata

#### Scenario: tunnel 在 endpoint 前失敗

- **WHEN** tunnel process 在輸出有效 RSD endpoint 前退出或逾時
- **THEN** 系統 SHALL 保持 device session non-ready 並回傳 tunnel failure
- **AND** helper SHALL 依既有 pending ownership 規則停止並回收該 process
- **AND** 系統 MUST NOT fallback 到 `remote start-tunnel` 或 native tunnel
