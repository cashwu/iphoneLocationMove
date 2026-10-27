# Acceptance Results — fix-ios-27-2-classic-tunnel

## 環境

- 日期：2026-10-27
- Host：macOS 27.2（26B123），Apple Silicon
- Device：iPhone18,1，iOS 27.2（24B119），USB
- Build：`Scripts/package-app.sh --version 1.0.8` 產生的 signed Release App（Apple Development 簽署）與 `build/iPhoneLocationMove-1.0.8.dmg`
- Pinned runtime：`pymobiledevice3==11.13.0`（`/Library/Application Support/iPhoneLocationMove/TunnelRuntime/pymobiledevice3-11.13.0`，沿用）

## 實機驗收（task 1.3 verification）

使用者以 signed App 1.0.8 執行下列清單後回報「可以了」：

1. 結束舊版並啟動新版 App，於管理員授權提示核准 helper 更新（`SMJobBlessPrivilegedHelperInstaller.installed()` 以位元組比對偵測到 helper 不一致）。
2. USB 連接 iPhone，App 未再顯示「USB tunnel 失敗」並進入 ready。
3. 設定定位，iPhone 位置成功改變。
4. 執行路線模擬連續至少 3 分鐘，未出現 tunnel／DVT 中斷。

結果：passed（使用者手動確認）。

## 修正前 baseline（red）

同一環境以 1.0.7 顯示「USB tunnel 失敗：The tunnel process exited before becoming ready.」；直接執行 `pymobiledevice3==11.13.0 remote start-tunnel --native --script-mode` 時，裝置的 service port 一律 `ConnectionRefusedError(61)`。

## 自動回歸

- `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`：271 tests，0 failures（`** TEST SUCCEEDED **`）。
- `Scripts/package-app.sh --version 1.0.8`：清理、Xcode tests、Python protocol tests、Release build、App／Helper 簽章與雙向 SMJobBless trust contract 驗證、DMG 建立全部 `[OK]`。
- Task 1.1 primary（`RuntimeManagerTests`，12 tests）與 regression（`DeviceSetupStoreTests`、`PymobiledeviceAdapterTests`）通過；task 1.2 primary（`TunnelHelperContractTests`，14 tests）與 regression（`PymobiledeviceAdapterTests`、`DisconnectReconnectIntegrationTests`）通過。

## 未執行

- `iPhoneLocationMoveTunnelHelper/Acceptance/run-production-acceptance.sh` 的 full negative／cleanup suite 本次未執行，不宣稱其 individual cases 或 final uninstall 通過。
