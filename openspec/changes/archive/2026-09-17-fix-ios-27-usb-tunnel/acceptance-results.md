# Acceptance Results

日期：2026-09-17

## 完成結論

在 macOS 27 上建置並以 Apple Development identity簽署 App後，使用者以 USB連接 iOS 27實機，確認 App可正常連線、操作並成功模擬定位。此結果穿越 signed App、real XPC、embedded privileged helper與 embedded wheelhouse的主要正向流程。

## 實機正向證據

- 環境：macOS 27、iOS 27、Xcode 27.0。
- Build：`xcodebuild build -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -configuration Debug -destination platform=macOS -derivedDataPath /tmp/iphone-location-move-acceptance/DerivedData`。
- Build結果：`** BUILD SUCCEEDED **`；App與 embedded helper均由 Apple Development identity簽署。
- 使用者觀察：實機可連接、可操作，定位功能成功。

## 自動驗證

- 完整 macOS test suite：272 tests、0 failures，`** TEST SUCCEEDED **`。
- Generator unittest：8 tests、0 failures，`OK`。
- Offline wheelhouse：以 `/usr/bin/python3` 建立乾淨 venv，使用 `--no-index --find-links iPhoneLocationMoveTunnelHelper/Resources/tunnel-wheelhouse` 安裝 `pymobiledevice3==11.13.0`成功。
- Acceptance runner：`bash -n`成功；帶額外參數時拒絕並回報 `this fixed runner accepts no arguments`；非 root執行時拒絕並回報 `this runner must run as root`。
- Residual scan：acceptance assets、README、helper與 contract tests未將 `TunnelRuntime/current`、`pymobiledevice3-9.36.3` 或錯誤的 `PrivilegedHelperTools/...TunnelRuntime` 當作 active runtime。
- Worktree whitespace validation：`git diff --check`成功。

## 未執行的額外 hardening

未以 `sudo` 執行 `run-production-acceptance.sh` 的完整 negative／cleanup suite，因此不宣稱 endpoint-timeout、runtime-seal-tamper、invalid-signature、team-id-mismatch或 final uninstall個別通過。使用者已明確接受以實機主要正向流程與上述完整自動驗證作為本次修復完成及封存標準。
