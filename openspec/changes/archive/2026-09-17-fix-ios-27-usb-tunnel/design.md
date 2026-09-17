## Context

`RuntimeManager.hasRequiredCapabilities` 目前以 `usbmux list --help`、`lockdown start-tunnel --help` 的 `--script-mode` 與 DVT simulate-location 的 `--rsd` 判斷 user runtime 是否相容；`FoundationTunnelProcessLauncher.launch` 再由 privileged helper 執行相同的 classic `lockdown start-tunnel`。helper 的 `EmbeddedDigestTable.validate`、`PinnedTunnelRuntimeInstaller` 與 `GeneratedTunnelTrustAnchor` 固定信任 `pymobiledevice3==9.36.3` offline wheelhouse，production runtime 固定安裝在 `/Library/Application Support/iPhoneLocationMove/TunnelRuntime/current`。

measured reproduction 使用 macOS 27.0（26A428）、arm64 與 USB iOS 27.0（24A437）：App 的 USB discovery、trust、Developer Mode、DDI 與 reconcile 均成功，但四次既有流程皆在 tunnel process 回傳 endpoint 前退出。相同環境執行 `pymobiledevice3==11.13.0 remote start-tunnel --native --script-mode --udid <deviceID>` 已回傳有效 RSD address／port，證明 native `remoted` transport 是可用的 distinguishing path。

現有 `TunnelLeaseManager` 已在 process launch 後、endpoint readiness 前建立 `PendingTunnelStart` ownership，並由 interruption／invalidation、timeout、stop 與 reconcile 負責回收；本次不改變這個 state machine。現有 persistent diagnostics 只允許 termination status 與 stderr byte count 等 allowlist metadata，本次也不擴張 raw stderr 的持久化範圍。

## Goals / Non-Goals

### Goals

- 讓 macOS 27 上的 iOS 27 USB iPhone 使用 pinned native tunnel 成功取得 RSD endpoint，並沿既有流程完成 DVT readiness。
- 只沿用同時具備 USB discovery、host policy 所需 tunnel surface 與 DVT `--rsd` 能力的 user runtime。
- 讓 system launchd 中的 privileged helper 明確連到 verified caller 所屬 user domain 的 `remotepairingd`，不依賴隱含的 current user 推測。
- 以版本化 root runtime 目錄完成 pinned runtime 升級，保留同版本 seal／owner／mode／digest drift 的 fail-closed 行為。
- 保持 typed XPC、caller trust、lease ownership、timeout、reconcile、DVT helper protocol 與定位行為不變。

### Non-Goals

- 不移除 privileged helper 或把 tunnel ownership 搬到 App process。
- 不新增失敗後 transport fallback state machine；macOS 27+ 使用 native policy，macOS 13–26 保留既有 classic policy。
- 不改變 USB selection、DDI、DVT mutation、simulation 或 reconnect contract。
- 不自動修復或刪除驗證失敗的同版本 root runtime。
- 不將 raw tunnel stderr、device ID 或 RSD endpoint寫入 persistent diagnostics。

## Decisions

### 1. 固定升級到 `pymobiledevice3==11.13.0`

`iPhoneLocationMove/Device/Resources/pymobiledevice3.lock` 作為 App user runtime pin；helper offline wheelhouse 必須由相同 requirement 的完整 transitive wheel set重建。helper 內建立 `TunnelRuntimePin`，集中保存 requirement 與 versioned directory component；`EmbeddedDigestTable.validate`、production destination 與 contract tests 均使用該 pin。generator 讀取 lockfile、確認 wheelhouse 中存在對應的 `pymobiledevice3` wheel，再輸出 manifest 與 `GeneratedTunnelTrustAnchor.swift`，避免 generator 另有獨立版本常數。

選擇 `11.13.0` 是使用者要求修復當日可取得、且 measured native tunnel 已成功的固定版本；這是 contract value，不是自動追蹤 latest。

### 2. capability probe 依 host policy 驗證 tunnel surface

`RuntimeManager.hasRequiredCapabilities` 依序執行：

1. `usbmux list --help`，要求 exit code 0；
2. macOS 27+ 執行 `remote start-tunnel --help`，要求 exit code 0，且 combined output 同時包含 `--native` 與 `--script-mode`；macOS 13–26 維持 `lockdown start-tunnel --help` 並要求 `--script-mode`；
3. `developer dvt simulate-location set --help`，要求 exit code 0，且 combined output 包含 `--rsd`。

任何一步不符即視為不相容，繼續既有 App-managed pinned install path。仍以 capability 而非版本字串作為 runtime selection contract。host policy 是啟動前的單一決策，不在 process failure 後切換 transport；這保留專案 macOS 13+／iOS 17+ 的既有 classic 行為，同時把已重現的 macOS 27 路徑切到 native。upstream 的 [iOS 17+ tunnel support matrix](https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/ios17-tunnels.md) 亦將 macOS 列為 native/no-root 支援 host，但本變更只在已實測的 macOS 27+ 啟用該分支。

### 3. helper 依 host policy 啟動固定 tunnel command

`TunnelProcessLaunching.launch` 增加 `targetUserID: UInt32`，`TunnelLeaseManager.startTunnel` 只傳入 `VerifiedCaller.identity.effectiveUserIdentifier`。macOS 27+ production launcher 的 arguments 固定為：

`remote start-tunnel --native --script-mode --udid <validated-device-id>`

launcher 以每次 launch 新建的 environment 在既有固定 `PATH`、`PYTHONDONTWRITEBYTECODE=1`、`PYTHONNOUSERSITE=1` 之外加入 `PYMOBILEDEVICE3_NATIVE_TARGET_UID=<decimal verified caller UID>`。macOS 13–26 的 arguments 維持 `lockdown start-tunnel --script-mode --udid <validated-device-id>`，且不設定 native target UID。兩個分支都不接受 caller 提供的 environment、command 或 arguments；device ID 仍先由 `DeviceID(validating:)` 驗證。這讓 root helper 在 macOS 27+ 使用 upstream daemon embedding boundary 連至正確 per-user launchd domain，同時保持 XPC surface 與較早 host transport 不變。

### 4. root runtime 使用 pinned-version 目錄，不覆寫 `current`

production destination 改為：

`/Library/Application Support/iPhoneLocationMove/TunnelRuntime/pymobiledevice3-11.13.0`

新 helper 只驗證／執行此目錄。舊 `current` 或其他版本目錄不會被新 helper 執行，也不會因版本不符而被刪除；既有 README uninstall 仍移除整個 `TunnelRuntime` parent。對目前 pinned-version 目錄，原有 seal、完整 file set、owner、mode、symlink 與 digest validation 完整保留，任一失敗仍回傳 runtime-integrity error，MUST NOT launch process。

採用版本化目錄而非自動 replacement，是為了不把「舊版合法內容」與「目前版本遭竄改」混成同一修復分支。

### 5. 驗證分成 deterministic contract 與 production acceptance

TDD 先讓下列 deterministic assertions 在舊實作失敗：

- macOS 27+ user runtime probe 必須要求 `remote start-tunnel` 的 `--native` 與 `--script-mode`；
- host policy 必須在 macOS 27+ 選 native、在 macOS 13–26 選 classic，且 process failure 後不得切換；
- generator 必須從唯一 lock requirement 導出 primary wheel／trust anchor，且對缺失、額外 payload 與版本不一致 fail closed；
- launcher 必須依 host policy 產生固定 arguments，且 native target UID 只能來自 verified caller；
- trust anchor build plan、wheel filename、requirement 與 versioned destination 必須一致；
- legacy `current` sibling 必須保持內容與 metadata 不變，且不得成為 executable source；
- timeout、duplicate start、owner invalidation、reconcile、runtime tamper 與 bounded stderr既有 contract tests保持通過。

production acceptance 新增固定 `device-session-ready` case，從 signed App 的實際 preparation path執行至 DVT ready／device session ready，而不只直接呼叫 `LiveTunnelClient`。本次修復的完成證據採用 macOS 27 + iOS 27 signed App實機正向操作成功，搭配完整 macOS自動測試、generator測試與 offline wheelhouse安裝驗證。固定、不可接受任意參數的 `run-production-acceptance.sh` 仍提供 real XPC／real helper boundary 的 negative／cleanup hardening suite；該 suite未完整執行時必須在 acceptance result明確記錄，不得宣稱其 individual negative cases或 final uninstall已通過，但不阻擋本次修復完成與封存。

## Implementation Contract

1. `RuntimeManager.hasRequiredCapabilities` MUST 使用本設計列出的 host-conditional probes；在 macOS 27+，只具備 classic `lockdown start-tunnel` 的 executable MUST NOT 回傳 `.ready`；在 macOS 13–26，既有 classic capability MUST 保持可用。
2. `TunnelRuntimePin.requirement` MUST 等於 lockfile 的唯一有效 requirement `pymobiledevice3==11.13.0`；`TunnelRuntimePin.directoryName` MUST 唯一對應該版本。
3. `generate_tunnel_trust_anchor.py` MUST fail closed：lockfile 缺失、不是唯一 pinned requirement、wheelhouse 缺少對應 primary wheel、存在非 wheel payload或 manifest generation 不一致時不得輸出新 trust anchor。
4. `GeneratedTunnelTrustAnchor.digestTable.buildPlan.requirement` MUST 使用 `TunnelRuntimePin.requirement`，payload entries 與 `runtime-manifest.json` byte-derived SHA-256 MUST 一致。
5. production `PinnedTunnelRuntimeInstaller.destinationURL` MUST 指向 `TunnelRuntimePin.directoryName` 的版本化 root-owned directory；MUST NOT fallback 到舊 `current`，也 MUST NOT 因新版本啟動而刪除或修改它。contract test MUST 以 sentinel legacy sibling證明其內容與 metadata不變。
6. `TunnelLeaseManager.startTunnel` MUST 在 caller code-signature verification 與 `DeviceID` validation 後，將 `VerifiedCaller.identity.effectiveUserIdentifier` 傳給 launcher。unverified request MUST NOT reach process launch。
7. `FoundationTunnelProcessLauncher` MUST 依 host policy只執行固定 arguments：macOS 27+ 使用 native command並將十進位 target UID放入 `PYMOBILEDEVICE3_NATIVE_TARGET_UID`，macOS 13–26 使用 classic command且不設定該變數；MUST NOT 接受任意 command、額外 flag 或 caller-supplied environment，也 MUST NOT 在 launch failure後改走另一 transport。
8. endpoint parse、15 秒 timeout、pending deduplication、lease ID、status、stop、owner invalidation、reconcile 與 stderr drain boundaries MUST 保持既有行為。
9. native process 在 endpoint 前退出時，App MUST 保持 non-ready 並回傳 tunnel failure；不得 fallback 到未經 capability probe／trust anchor驗證的 transport。
10. completion acceptance MUST 使用 signed App、embedded helper、embedded wheelhouse 與一台 USB iOS 27 device穿越 real XPC boundary，且實機正向流程 MUST 實際完成連線、操作與定位；fake launcher、user-space-only CLI或只有 tunnel status成功不得取代這項證據。
11. acceptance result MUST 同時保存完整 macOS自動測試、generator測試、offline wheelhouse安裝與 runner fail-closed smoke checks。`cases.json` 的 full negative／cleanup suite未執行時 MUST 明確標示為未執行，MUST NOT 將其 individual cases或 final uninstall記為通過；此額外 hardening evidence不作為本次完成與封存的必要條件。
12. persistent diagnostics MUST 延續 allowlist contract，不新增 raw stderr tail、RSD endpoint、device identifier或座標。

## Risks / Trade-offs

- native tunnel 依賴 macOS `remotepairingd`／`remoted`。以 explicit `--native` 與 target UID消除 transport 與 user-domain歧義，但若 OS service 本身不可用，連線會 fail closed，不會靜默回退 classic tunnel。
- wheelhouse 升級會改動大量 binary wheel payload與 generated digest table。generator 的 lockfile／primary-wheel一致性檢查、manifest digest與 package tests用來防止版本或 payload drift；實作 review 必須把 binary變更限制在 declared wheelhouse directory。
- 版本化 root runtime會保留舊 `current` 目錄直到使用者 uninstall。這增加有限磁碟占用，但避免把 tamper 當成 upgrade 自動覆寫；README 明確說明新路徑與整體移除方式。
- root helper跨 user domain存取 `remotepairingd` 依賴 upstream 的 `PYMOBILEDEVICE3_NATIVE_TARGET_UID` embedding contract。deterministic test驗證 UID來源與 environment，real acceptance驗證 system launchd boundary。

## Decision History

- 2026-09-17：使用者在 macOS 27 + iOS 27 signed App實機確認可連線、操作與定位，並明確決定以該正向流程及完整自動測試作為本次完成標準。完整 production negative／cleanup suite保留為後續 hardening，不阻擋本 change封存；未執行項目必須如實記錄。
