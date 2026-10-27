## Context

`FoundationTunnelProcessLauncher`（`iPhoneLocationMoveTunnelHelper/main.swift`）目前以 `TunnelHostPolicy(operatingSystemVersion:)` 決定 tunnel command：macOS 27+ 為 `.native`，執行 `remote start-tunnel --native --script-mode --udid <id>` 並以 `TunnelHostPolicy.environment(base:targetUserID:)` 設定 `PYMOBILEDEVICE3_NATIVE_TARGET_UID`；macOS 13–26 為 `.classic`，執行 `lockdown start-tunnel --script-mode --udid <id>`。`TunnelLeaseManager.startTunnel` 以 `processLauncher.launch(runtime:deviceID:targetUserID:)` 傳入 `caller.identity.effectiveUserIdentifier`，而 `targetUserID` 只被 native 分支使用。`RuntimeManager.hasRequiredCapabilities`（`iPhoneLocationMove/Device/RuntimeManager.swift`）同樣以 `hostOperatingSystemVersion.majorVersion >= 27` 選擇 `remote start-tunnel --help` 加 `--native`／`--script-mode`，否則為 `lockdown start-tunnel --help` 加 `--script-mode`；`RuntimeManager.Configuration.hostOperatingSystemVersion` 只供這個 probe 使用。

measured（2026-10-27，macOS 27.2 26B123、USB iPhone18,1 iOS 27.2 24B119；方法：以與 helper／App 相同的 pinned 版本直接執行 CLI 並逐步連線；結果來源：本次對話的 CLI 輸出）：

1. `pymobiledevice3==11.13.0 remote start-tunnel --native` 的 RSD handshake 成功，但所有宣告的 service port 都 `ConnectionRefusedError(61)`，tunnel process 在輸出 endpoint 前以 `failed to complete RSD handshake over the native tunnel` 退出。`11.45.0 --native` 的後續 `lockdown info --rsd` 同樣被拒。
2. `11.45.0` classic `remote start-tunnel` 在 `/usr/bin/python3`（3.9.6，LibreSSL 2.8.3）上：預設 QUIC 回報 `iOS 18.2+ removed QUIC tunnel support`；`-p tcp` 回報 LibreSSL 無法選擇 PSK cipher。
3. 以 `/usr/bin/python3` 建立 venv、`--no-index` 從 `iPhoneLocationMoveTunnelHelper/Resources/tunnel-wheelhouse/` 安裝 `pymobiledevice3==11.13.0`，以 root 執行 `lockdown start-tunnel --script-mode --udid <id>` 成功輸出 RSD address／port；App user runtime（`11.13.0`）執行 `lockdown info --rsd <address> <port>` 回傳 `ProductVersion` `27.2`。過程不需要額外的 remote pairing 同意。此 measurement 經 `sudo` 執行，environment 與 helper 不同（helper 在 system launchd domain 下只帶 `PATH`、`PYTHONDONTWRITEBYTECODE`、`PYTHONNOUSERSITE`，沒有使用者 `HOME` 或 `SUDO_UID`）；lockdown 路徑預期使用 usbmuxd 管理的 system pair record 而非 `HOME` 下的 pair record，但這只能由 task 1.3 經 SMJobBless helper 的實機結果證實。

## Goals / Non-Goals

### Goals

- 讓 macOS 27.2 + iOS 27.2 USB iPhone 經 helper 取得可用的 RSD endpoint，並沿既有流程完成 DVT ready 與定位。
- 所有受支援 macOS 使用單一、固定的 classic tunnel command 與 capability probe。
- 移除只為 native 分支存在的 host-version 分支、`targetUserID` plumbing 與 `PYMOBILEDEVICE3_NATIVE_TARGET_UID`。
- 保持 pinned runtime、trust anchor、caller trust、lease ownership、timeout、reconcile 與 diagnostics contract 不變。

### Non-Goals

- 不升級 `pymobiledevice3`、不重建 wheelhouse／manifest／trust anchor、不更換 interpreter。
- 不新增 transport fallback 或依 iOS 版本選擇 transport。
- 不改變 XPC request／response 型別或 lease state machine。

## Decisions

### 1. 所有受支援 macOS 固定使用 classic lockdown tunnel

刪除 `TunnelHostPolicy`。`FoundationTunnelProcessLauncher` 不再接受 `operatingSystemVersion`，其 arguments 固定為 `["lockdown", "start-tunnel", "--script-mode", "--udid", deviceID.rawValue]`，environment 固定為 `FoundationTunnelProcessLauncher.processEnvironment` 的副本（`PATH`、`PYTHONDONTWRITEBYTECODE=1`、`PYTHONNOUSERSITE=1`），不設定 `PYMOBILEDEVICE3_NATIVE_TARGET_UID` 或任何 caller-supplied 值。

選擇此路徑的理由：它是 measured 唯一在現有 `/usr/bin/python3` 與 pinned `11.13.0` 上於 iOS 27.2 成功的路徑，也是 macOS 13–26 早已使用的 policy，因此較早 host 的 transport contract 不變（見 signal `host-support-matrix-transport-regression`）。

### 2. 移除 `targetUserID` launcher 參數

`TunnelProcessLaunching.launch` 改為 `launch(runtime: InstalledTunnelRuntime, deviceID: DeviceID) throws -> TunnelProcessControlling`；`TunnelLeaseManager.startTunnel` 的呼叫點同步移除 `targetUserID:`。caller code-signature verification、`DeviceID(validating:)` 以及 pending／lease 以 `caller.identity` 記錄 ownership 的順序不變；unverified request 仍 MUST NOT 到達 launch。移除 native 分支後，macOS 27+ 的 device access 邊界回到 macOS 13–26 既有的 system usbmux pair record 模型：verified caller 身分只決定 XPC trust 與 lease ownership，不再決定 tunnel 連到哪個 user domain。

### 3. capability probe 不再依 host version 分支

`RuntimeManager.hasRequiredCapabilities` 固定依序執行：`usbmux list --help`（exit 0）、`lockdown start-tunnel --help`（exit 0 且 combined output 含 `--script-mode`）、`developer dvt simulate-location set --help`（exit 0 且含 `--rsd`）。移除 `hostOperatingSystemVersion` 參數，以及 `RuntimeManager.Configuration.hostOperatingSystemVersion` 欄位、其 init 參數與 `Equatable` 比較；`RuntimeManagerTests` 的 harness 同步移除該輸入。仍以 capability 而非版本字串判定相容。

### 4. pinned runtime 維持 `11.13.0`

`iPhoneLocationMove/Device/Resources/pymobiledevice3.lock`、`TunnelRuntimePin`、`GeneratedTunnelTrustAnchor.swift`、offline wheelhouse 與 `/Library/Application Support/iPhoneLocationMove/TunnelRuntime/pymobiledevice3-11.13.0` 不變。使用者機器上已安裝且 sealed 的 runtime 在升級 App 後直接沿用，不重新安裝。

### 5. 驗證

TDD 先讓以下 deterministic assertions 在舊實作失敗。red 階段沿用既有 seam：`RuntimeManagerTests` 以 `hostOperatingSystemVersion` 27 建構 configuration、`TunnelHelperContractTests` 以 `FoundationTunnelProcessLauncher(operatingSystemVersion:)` 27 建構 launcher，使 red 不依賴測試機 OS；production 移除 seam 後，測試同步改為無 host-version 參數的 API。

- `RuntimeManagerTests`：預設 host 的 compatible probe 序列為 `usbmux list --help`、`lockdown start-tunnel --help`、`developer dvt simulate-location set --help`；只具備 `remote start-tunnel --native` 而 `lockdown start-tunnel --help` 缺 `--script-mode` 的 executable 不得為 `.ready`。
- `TunnelHelperContractTests`：`FoundationTunnelProcessLauncher` 以 capture fixture 驗證 arguments 等於 `["lockdown", "start-tunnel", "--script-mode", "--udid", deviceID]`，`PYMOBILEDEVICE3_NATIVE_TARGET_UID` 與 `SUDO_UID` 皆不存在；既有 launch、timeout、ownership、reconcile、runtime tamper 與 legacy sibling tests 保持通過。
- 須改寫或移除、而非原樣保留的既有測試：`RuntimeManagerTests` 的 `testCompatibleExistingInstallationUsesHostPolicyCapabilityProbesWithoutCreatingVenv`（預期序列改為 `lockdown`）、`testMacOS27RejectsClassicOnlyTunnelCapability`（反轉為只具備 native 能力者不相容）、`testMacOS13Through26KeepsClassicTunnelCapability`（移除 host-version 輸入）以及其他 stub `Options: --native --script-mode` 的案例；`TunnelHelperContractTests` 中斷言 `launcher.launches[0].2 == fixture.identity.effectiveUserIdentifier` 的 verified UID oracle 移除（ownership 由既有 `.leaseNotOwned` intruder 斷言承接）、兩個 fake launcher 的 `targetUserID` 簽章移除、`testFoundationLauncherUsesNativeArgumentsAndVerifiedUID`／`native-launch` case 改為 fixed classic launch 測試。

完成證據：完整 macOS 自動測試，以及使用者在 signed App（macOS 27.2 + iOS 27.2 USB）實機確認可連線、操作並成功定位，記錄於 `openspec/changes/fix-ios-27-2-classic-tunnel/acceptance-results.md`。

## Implementation Contract

1. `FoundationTunnelProcessLauncher.launch` MUST 對任何 host version 只執行 `lockdown start-tunnel --script-mode --udid <validated-device-id>`；MUST NOT 含 `remote`、`--native` 或其他 flag。
2. launcher environment MUST 等於 `FoundationTunnelProcessLauncher.processEnvironment`；MUST NOT 含 `PYMOBILEDEVICE3_NATIVE_TARGET_UID`、`SUDO_UID` 或 caller-supplied 值。
3. `TunnelHostPolicy` MUST 被移除；`TunnelProcessLaunching.launch` MUST NOT 接受 `targetUserID`。
4. `TunnelLeaseManager.startTunnel` MUST 在 caller verification 與 `DeviceID` validation 後才呼叫 launcher；pending deduplication、15 秒 endpoint timeout、stop、owner invalidation、reconcile 與 stderr drain 行為 MUST 不變。
5. `RuntimeManager.hasRequiredCapabilities` MUST 在所有 host 使用 Decision 3 的三個 probes；`RuntimeManager.Configuration` MUST NOT 保留 `hostOperatingSystemVersion`。
6. pinned requirement、wheelhouse、`GeneratedTunnelTrustAnchor.swift` 與 versioned runtime destination MUST 不變。
7. tunnel process 在 endpoint 前退出或逾時時，App MUST 保持 non-ready 並回傳 tunnel failure；MUST NOT fallback 到其他 transport。
8. persistent diagnostics MUST 維持既有 allowlist，不新增 raw stderr、RSD endpoint 或 device identifier。

## Risks / Trade-offs

- iOS 27.0–27.1 裝置改走 lockdown 路徑未經本次實測。前一個 change 記錄的 iOS 27.0 classic 失敗發生在 `pymobiledevice3==9.36.3`，不是目前 pinned 的 `11.13.0`；本次只在 iOS 27.2 measured 成功。若舊 iOS 27 小版本失敗，App 仍 fail closed 顯示 tunnel failure，使用者可更新 iOS。
- macOS 27 搭配 iOS 17.0–26.x 裝置原本走 native，本次一併改走 lockdown `CoreDeviceProxy`，未經實測；`CoreDeviceProxy` 一般需要 iOS 17.4+，因此 iOS 17.0–17.3 可能 fail closed。這與 macOS 13–26 既有 policy 的行為一致，屬刻意接受的取捨。
- upstream #1994 描述的 iOS 27.2 單一 RSD 連線驅逐是否也作用於 lockdown tunnel 上的長時間 RSD／DVT 連線未經觀察；measured 只有單次 `lockdown info --rsd`。task 1.3 以持續 route simulation 檢驗；若發生驅逐，既有 reconnect／recovery 行為會處理，但需另開 change 調查。
- 未來 Apple 若移除 usbmux 上的 `CoreDeviceProxy`，此路徑會失效；屆時需要支援 TCP PSK 的 interpreter（例如 root-owned Python 3.13+），屬另一個 change 的範圍。
- 移除 native 分支後，若日後需要重新支援 native，必須重新設計 target UID 傳遞；本次不保留未使用的 plumbing，以免留下沒有 caller 的抽象。
