## Summary

修正 macOS 27.2 搭配 iOS 27.2 時，App 顯示「USB tunnel 失敗：The tunnel process exited before becoming ready.」而無法進入 device session ready 的問題：privileged helper 在所有受支援 macOS 改用 classic `lockdown start-tunnel --script-mode --udid <deviceID>`，移除只在 iOS 27.0 有效、在 iOS 27.2 失效的 macOS native tunnel 分支；pinned `pymobiledevice3==11.13.0` 與 sealed offline runtime 維持不變。

## Motivation

這是 bug fix。前一個 change（archive `2026-09-17-fix-ios-27-usb-tunnel`）讓 macOS 27+ 的 helper 固定執行 `remote start-tunnel --native --script-mode`。2026-10-27 在 macOS 27.2（26B123）、USB iPhone18,1 iOS 27.2（24B119）上 measured 重現（方法：直接以 App user runtime 與 helper 相同的 pinned 版本執行 tunnel command 並逐步連線；結果來源：本次對話的 CLI 輸出）：

- native tunnel 介面與 RSD handshake 成功，但裝置宣告的所有 service port（`com.apple.mobile.lockdown.remote.trusted`、`com.apple.mobile.lockdown.remote.untrusted`、`com.apple.instruments.dtservicehub`、`com.apple.dt.testmanagerd.remote` 等）一律 `ConnectionRefusedError(61)`；tunnel process 因此以 `failed to complete RSD handshake over the native tunnel` 退出，helper 回傳 `processExited`。
- 上游 `pymobiledevice3==11.45.0` 原始碼說明 iOS 27.2 在 native tunnel 上只保留單一 RSD 連線，與 host `remoted` 互相驅逐（upstream #1994），因此上游已把 native 改為 opt-in；實測 11.45.0 `--native` 也在後續 `lockdown info --rsd` 被拒。
- 上游 classic `remote start-tunnel` 在 helper 使用的 `/usr/bin/python3`（3.9.6，LibreSSL 2.8.3）上不可行：預設 QUIC 被 iOS 拒絕（`iOS 18.2+ removed QUIC tunnel support`），強制 `-p tcp` 則因 LibreSSL 無法選擇 PSK cipher 而失敗。
- classic `lockdown start-tunnel --script-mode --udid <deviceID>` 以與 helper 相同的 interpreter 與 pinned runtime（`/usr/bin/python3` 3.9.6 + 由 repo 內嵌 offline wheelhouse 安裝的 `pymobiledevice3==11.13.0`，經 `sudo` 以 root 執行；environment 與 helper 不同，helper environment 下的結果由實機驗收證實）成功輸出 RSD address／port；App user runtime（`pymobiledevice3==11.13.0`）以 `lockdown info --rsd <address> <port>` 透過該 tunnel 取得 `ProductVersion` `27.2`。此路徑使用既有 lockdown 配對（usbmux 上的 `CoreDeviceProxy`），不需要額外的 remote pairing 同意。

## Proposed Solution

- privileged helper 的 tunnel launcher 在所有受支援 macOS（13+）固定執行 `lockdown start-tunnel --script-mode --udid <validated-device-id>`，移除 macOS 27+ 的 native 分支與 `PYMOBILEDEVICE3_NATIVE_TARGET_UID` environment；launcher environment 回到固定的 `PATH`、`PYTHONDONTWRITEBYTECODE=1`、`PYTHONNOUSERSITE=1`。
- 因 native 分支移除，verified caller UID 不再需要傳入 launcher；`TunnelProcessLaunching.launch` 移除 `targetUserID` 參數，caller trust 與 lease ownership 仍以 `VerifiedCaller` 為準。
- `RuntimeManager.hasRequiredCapabilities` 在所有 host 使用同一組 probe：`usbmux list --help`、`lockdown start-tunnel --help` 含 `--script-mode`、`developer dvt simulate-location set --help` 含 `--rsd`；移除只為 native 分支存在的 host-version 輸入。
- 保留 pinned `pymobiledevice3==11.13.0`、offline wheelhouse、`GeneratedTunnelTrustAnchor`、versioned runtime 目錄 `pymobiledevice3-11.13.0` 與所有 seal／digest／ownership 驗證；已安裝的 root runtime 直接沿用。
- 將 production acceptance 手冊中只匹配 `remote` tunnel 的 process pattern 同步為與 runner 相同的 `pymobiledevice3.*start-tunnel`。
- 以 TDD 更新 deterministic contract tests，並以 signed App 在 macOS 27.2 + iOS 27.2 實機完成連線、操作與定位作為完成證據。

## Non-Goals

- 不升級 `pymobiledevice3`，不重建 wheelhouse、runtime manifest 或 trust anchor。
- 不改變 privileged helper、SMJobBless、typed XPC surface、`TunnelLeaseManager` 的 pending／lease／timeout／reconcile state machine，或 15 秒 endpoint timeout。
- 不新增 transport fallback、依 iOS 版本切換 transport，或保留 native tunnel 作為選項。
- 不更換 helper 使用的 `/usr/bin/python3`，也不引入其他 Python interpreter。
- 不改變 USB selection、DDI、DVT、定位、route simulation 或 reconnect 行為。
- 不把 raw stderr、RSD endpoint 或 device identifier 寫入 persistent diagnostics。

## Alternatives Considered

- 升級到 `pymobiledevice3==11.45.0` 並使用上游預設的 classic `remote start-tunnel`：未採用。它在 Python <3.13 預設 QUIC（iOS 已移除），TCP 需要 OpenSSL PSK，而 helper 的 `/usr/bin/python3` 是 LibreSSL 2.8.3；measured 兩者皆失敗。另需處理 `srptools` 2.0.0 對 `verify_proof(bytes)` 的語意變更，以及首次 remote pairing 同意可能超過 15 秒 timeout。
- 讓 helper 改用 root-owned Python 3.13+：未採用。會改變 privileged runtime 的 interpreter trust boundary，且 classic lockdown 路徑已在現有 interpreter 上成功。
- 保留 native 分支並依 iOS 版本選擇 transport：未採用。native 在 iOS 27.2 已失效且上游已降為 opt-in；新增依裝置版本切換的 policy 會擴大 contract，而 lockdown 路徑已是 macOS 13–26 的既有 policy。
- 只升級 pin、繼續使用 native：未採用，measured 11.45.0 native 同樣被拒。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `ios-device-session`：tunnel capability probe 與 helper tunnel policy 在所有受支援 macOS 統一為 classic `lockdown start-tunnel --script-mode`；移除 macOS native tunnel 相容路徑。

## Impact

- Affected specs:
  - openspec/specs/ios-device-session/spec.md
- Affected code:
  - New:
    - openspec/changes/fix-ios-27-2-classic-tunnel/acceptance-results.md
  - Modified:
    - iPhoneLocationMove/Device/RuntimeManager.swift
    - iPhoneLocationMoveTunnelHelper/main.swift
    - iPhoneLocationMoveTests/RuntimeManagerTests.swift
    - iPhoneLocationMoveTests/TunnelHelperContractTests.swift
    - iPhoneLocationMoveTunnelHelper/Acceptance/PRODUCTION_ACCEPTANCE.md
  - Removed:
    - (none)
