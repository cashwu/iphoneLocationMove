## Summary

修正 macOS 27 搭配 iOS 27 時，App 仍使用舊版 `pymobiledevice3` 與 classic `lockdown start-tunnel`，導致 USB tunnel 子程序在回傳 RSD endpoint 前退出、裝置無法進入 ready 的問題。

## Motivation

目前專案固定使用 `pymobiledevice3==9.36.3`，runtime capability probe 與 privileged helper 也固定依賴 `lockdown start-tunnel --script-mode`。在 measured 環境 macOS 27.0（26A428）與 iOS 27.0（24A437）上，App 連續重試仍於 tunnel 階段失敗；相同 Mac、USB iPhone 與 prerequisite 狀態下，`pymobiledevice3==11.13.0 remote start-tunnel --native --script-mode` 已實測成功回傳 RSD endpoint。系統需要採用新版 macOS native tunnel 路徑，同時維持既有 caller trust、sealed offline runtime、lease ownership 與 fail-closed 邊界。

## Proposed Solution

- 將 App user runtime 與 privileged helper offline wheelhouse 的 pinned `pymobiledevice3` 升級到 `11.13.0`，同步重建 payload manifest 與 embedded digest trust anchor。
- 將 runtime capability probe 改為依 host policy 驗證 tunnel surface：macOS 27+ 要求 `remote start-tunnel` 的 `--native`／`--script-mode`，macOS 13–26 保留既有 `lockdown start-tunnel --script-mode`；兩者都要求 USB discovery 與 DVT simulate-location 的 `--rsd` 能力。
- 保留現有 typed XPC surface 與 `TunnelLeaseManager`。macOS 27+ 由 helper 執行 `remote start-tunnel --native --script-mode --udid <deviceID>`，並將已驗證 XPC caller 的 effective UID 以 `PYMOBILEDEVICE3_NATIVE_TARGET_UID` 傳給子程序，使 system launchd domain 能明確連到該登入使用者的 `remotepairingd` domain；較早的受支援 macOS 維持 classic command，不進行失敗後 fallback。
- 將新 pinned root runtime 安裝到版本化、root-owned、sealed 目錄，讓升級後的 helper 不會沿用舊版 runtime，也不會以刪除／重建方式掩蓋同版本 runtime 的 seal 或 digest drift。
- 以 deterministic command／environment／runtime trust tests、完整 macOS 自動測試，以及 macOS 27 + iOS 27 實機正向操作驗證完整 DVT-ready session與定位流程。production negative／cleanup runner保留為額外 hardening surface，但不再作為本次修復完成與封存的必要條件。

## Non-Goals

- 不移除或重新設計 privileged helper、SMJobBless、typed XPC surface、lease／reconcile state machine。
- 不改變定位 set／clear、route simulation、USB reconnect 或 DVT recovery 的使用者行為。
- 不支援非 macOS host，也不修改 global Python、Homebrew 或使用者既有 `pymobiledevice3` 安裝。
- 不把 raw stderr、RSD endpoint、device identifier 或其他敏感 tunnel detail寫入 persistent diagnostics。
- 不自動刪除或信任未通過現行 seal、owner、mode、file-set 與 digest 驗證的 root runtime。

## Alternatives Considered

- 僅升級 `pymobiledevice3`、繼續使用 `lockdown start-tunnel`：未採用，因為 measured 成功路徑是 macOS native tunnel，且 classic tunnel 仍保留額外 root TUN/TAP 與 TLS／PSK 相容風險。
- 將 tunnel process 完全移回 App user process：未採用，這會同時改寫 XPC、lease ownership、reconcile、installer 與 cleanup contract，超出本次相容性修復需要。
- 發現既有 `current` runtime 與新 trust anchor 不符時直接刪除重裝：未採用，因為無法可靠區分合法舊版本與遭竄改內容，會削弱既有 fail-closed tamper contract。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `ios-device-session`：相容 runtime 改以 macOS native tunnel capability 判定；iOS 27 裝置透過 pinned native tunnel 取得有效 RSD endpoint，升級與 tamper 路徑維持 fail closed。

## Impact

- Affected specs:
  - openspec/specs/ios-device-session/spec.md
- Affected code:
  - New:
    - openspec/changes/fix-ios-27-usb-tunnel/acceptance-results.md
    - iPhoneLocationMoveTunnelHelper/Scripts/tests/test_generate_tunnel_trust_anchor.py
    - iPhoneLocationMoveTunnelHelper/Acceptance/run-production-acceptance.sh
  - Modified:
    - iPhoneLocationMove/Device/Resources/pymobiledevice3.lock
    - iPhoneLocationMove/Device/RuntimeManager.swift
    - iPhoneLocationMoveTunnelHelper/main.swift
    - iPhoneLocationMoveTunnelHelper/Scripts/generate_tunnel_trust_anchor.py
    - iPhoneLocationMoveTunnelHelper/GeneratedTunnelTrustAnchor.swift
    - iPhoneLocationMoveTunnelHelper/Resources/tunnel-wheelhouse/
    - iPhoneLocationMove/App/iPhoneLocationMoveApp.swift
    - iPhoneLocationMoveTests/RuntimeManagerTests.swift
    - iPhoneLocationMoveTests/TunnelHelperContractTests.swift
    - iPhoneLocationMoveTests/AppLifecycleTests.swift
    - iPhoneLocationMoveTunnelHelper/Acceptance/cases.json
    - iPhoneLocationMoveTunnelHelper/Acceptance/prepare-endpoint-timeout.py
    - iPhoneLocationMoveTunnelHelper/Acceptance/PRODUCTION_ACCEPTANCE.md
    - README.md
  - Removed:
    - (none)
