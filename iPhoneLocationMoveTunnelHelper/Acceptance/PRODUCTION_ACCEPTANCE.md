# Production privileged-helper acceptance

本手冊只用固定 case、固定安裝位置與固定 `/tmp/iphone-location-move-acceptance` 工作目錄。DEBUG App runner 只接受：

```text
--privileged-helper-acceptance-case <PrivilegedHelperAcceptanceCase>
```

不得在 runner 後加入 command、path、interpreter、package、manifest、output path 或其他 argument。case 清單與預期結果以同目錄的 `cases.json` 為準。

## 1. 準備原始 signed App

連接且只保留一台 iOS 17+ USB iPhone，確認已信任 Mac、已開啟 Developer Mode。從 repository root 執行：

```sh
rm -rf /tmp/iphone-location-move-acceptance
mkdir -p /tmp/iphone-location-move-acceptance/results
xcodebuild build \
  -project iPhoneLocationMove.xcodeproj \
  -scheme iPhoneLocationMove \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/iphone-location-move-acceptance/DerivedData
```

固定 App 路徑：

```text
/tmp/iphone-location-move-acceptance/DerivedData/Build/Products/Debug/iPhoneLocationMove.app
```

先正常開啟原始 App，一次性完成 `SMJobBless` 管理員核准與 runtime 安裝；關閉 App 後才開始 case。核准前後記錄：

```sh
sudo launchctl print system/com.cash.iPhoneLocationMoveTunnelHelper
sudo stat -f '%Su:%Sg %Mp%Lp %N' \
  /Library/PrivilegedHelperTools/com.cash.iPhoneLocationMoveTunnelHelper \
  /Library/LaunchDaemons/com.cash.iPhoneLocationMoveTunnelHelper.plist \
  '/Library/Application Support/iPhoneLocationMove/TunnelRuntime/current' \
  '/Library/Application Support/iPhoneLocationMove/TunnelRuntime/current/runtime-seal.json'
sudo shasum -a 256 /Library/PrivilegedHelperTools/com.cash.iPhoneLocationMoveTunnelHelper
codesign -dv --verbose=4 /Library/PrivilegedHelperTools/com.cash.iPhoneLocationMoveTunnelHelper
```

## 2. 每個 case 的固定 evidence

每個 case 執行前後都執行以下 snapshot，保存到
`/tmp/iphone-location-move-acceptance/results/<case>-before.txt` 與
`<case>-after.txt`：

```sh
pgrep -alf 'iPhoneLocationMoveTunnelHelper|pymobiledevice3.*remote.*tunnel|TunnelRuntime' || true
sudo launchctl print system/com.cash.iPhoneLocationMoveTunnelHelper
sudo find '/Library/Application Support/iPhoneLocationMove/TunnelRuntime/current' \
  -xdev -print0 | sudo xargs -0 stat -f '%Su:%Sg %Mp%Lp %N'
```

runner stdout 是該 case 唯一的 lease／typed-error result，直接保存為
`/tmp/iphone-location-move-acceptance/results/<case>.json`。以原始 App 執行：

```sh
'/tmp/iphone-location-move-acceptance/DerivedData/Build/Products/Debug/iPhoneLocationMove.app/Contents/MacOS/iPhoneLocationMove' \
  --privileged-helper-acceptance-case positive-start
```

依序執行 `positive-start`、`pending-duplicate`、`lost-reply-retry`、
`connection-invalidation`、`app-termination` 與 `startup-reconcile`。
`connection-invalidation`／`app-termination` 的 after snapshot MUST 顯示相關
tunnel process count 回到 0；下一個 `startup-reconcile` MUST 成功。

## 3. Caller trust fixtures

固定建立兩份 copy：

```sh
cp -R \
  /tmp/iphone-location-move-acceptance/DerivedData/Build/Products/Debug/iPhoneLocationMove.app \
  /tmp/iphone-location-move-acceptance/signature-invalid.app
printf '\0' >> \
  /tmp/iphone-location-move-acceptance/signature-invalid.app/Contents/MacOS/iPhoneLocationMove

cp -R \
  /tmp/iphone-location-move-acceptance/DerivedData/Build/Products/Debug/iPhoneLocationMove.app \
  /tmp/iphone-location-move-acceptance/team-mismatch.app
codesign --force --deep --sign - \
  /tmp/iphone-location-move-acceptance/team-mismatch.app
```

兩份 copy 都只執行 `positive-start` 固定 case。保存 OS launch rejection 或 XPC
connection rejection 的 `tunnel-failure`；before／after process count MUST 相同，且
MUST NOT 建立 lease。
用 `codesign -dv --verbose=4` 保存原始 App 與兩份 copy 的 identifier／TeamIdentifier。

## 4. Runtime seal tamper fixtures

每個 tamper case 前先刪除 current runtime，再以原始 signed App 執行
`positive-start` 讓 helper 從已驗證的 wheelhouse 重新建立乾淨 runtime。只在
`/Library/Application Support/iPhoneLocationMove/TunnelRuntime/current` 進行以下
單一變更：

- missing：移除一個 seal 內列出的 generated file；
- extra：新增 `runtime/acceptance-extra.py`；
- symlink：將 generated executable 替換為指向 `/bin/false` 的 symlink；
- owner：將一個 generated file 改成登入使用者 owner；
- mode：將一個 generated file 改成 mode `0777`；
- digest：改寫 generated executable 內容後恢復原 mode；
- seal owner／mode：分別改變 `runtime-seal.json` owner 或 mode。

每次都執行 `runtime-seal-tamper`。結果 MUST 為 `passed: true` 且帶
`tunnel-failure` typed error，before／after tunnel process count MUST 都是 0。
完成單一 case 後立即刪除 current runtime，再由原始 signed App 重建，避免 tamper
互相污染。

`endpoint-timeout` 使用同目錄
`fixtures/endpoint-timeout.py` 的固定內容：由管理員將其複製成 root-owned mode
`0700` generated executable，依目前完整 file set
重新產生 root-owned mode `0600` seal，再執行 `endpoint-timeout`。runner MUST
收到 handshake timeout；15 秒後 after snapshot MUST 無 tunnel process。此 fixture
只能位於上述 root-owned current runtime，禁止讓 helper 執行 repository、
`/tmp` 或其他 user-writable path。

固定準備工具 `prepare-endpoint-timeout.py` 不接受任何參數，將相同 fixture 內容
直接寫入上述 root-owned executable 並重建完整 seal；它只供管理員授權的
acceptance 環境使用，不會編入 App 或 helper：

```sh
sudo /usr/bin/python3 \
  iPhoneLocationMoveTunnelHelper/Acceptance/prepare-endpoint-timeout.py
```

## 5. Uninstall 與最終 cleanup

完成所有 case 後執行固定 cleanup：

```sh
sudo launchctl bootout system/com.cash.iPhoneLocationMoveTunnelHelper || true
sudo rm -f /Library/PrivilegedHelperTools/com.cash.iPhoneLocationMoveTunnelHelper
sudo rm -f /Library/LaunchDaemons/com.cash.iPhoneLocationMoveTunnelHelper.plist
sudo rm -rf '/Library/Application Support/iPhoneLocationMove'
```

最終 MUST 同時確認：

```sh
test ! -e /Library/PrivilegedHelperTools/com.cash.iPhoneLocationMoveTunnelHelper
test ! -e /Library/LaunchDaemons/com.cash.iPhoneLocationMoveTunnelHelper.plist
test ! -e '/Library/Application Support/iPhoneLocationMove'
sudo launchctl print system/com.cash.iPhoneLocationMoveTunnelHelper
pgrep -alf 'iPhoneLocationMoveTunnelHelper|pymobiledevice3.*remote.*tunnel|TunnelRuntime'
```

最後兩個查詢預期找不到 service／process。將所有 JSON、snapshot、signature、
owner／mode／digest 與 cleanup 結果摘要追加到 change 的
`acceptance-results.md`，並逐項標明 `production` 或 `deterministic` evidence。
