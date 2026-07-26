# iPhone Location Move

以原生 SwiftUI 與 MapKit 製作的 macOS 定位模擬工具。透過 USB 控制一台
iOS 17+ iPhone，可設定單一位置，或沿 MapKit 步行路線在 A、B 兩點間移動。
路線支援 `1–7 km/h`、暫停、繼續，以及選用的往返循環。

目前的交付目標是使用 Apple Development 憑證，直接從本機 Xcode Build／Run。
不包含公證、Developer ID、Mac App Store 或可供其他人下載的安裝包。

## 環境需求

- macOS 13+
- Xcode，且已登入可用的 Apple Development 帳號
- Apple Silicon Mac（目前內嵌的 privileged tunnel wheelhouse 是 arm64）
- iOS 17+ iPhone
- 可傳輸資料的 USB 線
- iPhone 已解鎖、信任這台 Mac，且已開啟 Developer Mode
- Python 3.9+，或 PATH 中已有功能相容的 `pymobiledevice3`

開啟 Developer Mode：

1. 在 iPhone 前往「設定 → 隱私權與安全性 → 開發者模式」。
2. 開啟後依提示重新啟動 iPhone。
3. 重新解鎖並確認啟用。

## 從 Xcode 執行

1. 開啟 `iPhoneLocationMove.xcodeproj`。
2. Scheme 選擇 `iPhoneLocationMove`。
3. Destination 選擇 `My Mac`。
4. 確認 Signing & Capabilities 使用 Team `2LRM76M575`。
5. 按 Run（`⌘R`）。

專案已設定以 Apple Development 簽署 App 與
`com.cash.iPhoneLocationMoveTunnelHelper`。如果改用另一個 Team，必須同步更新：

- `iPhoneLocationMove/project.yml` 的 `DEVELOPMENT_TEAM`
- `iPhoneLocationMove/Info.plist` 的 `SMPrivilegedExecutables`
- `iPhoneLocationMoveTunnelHelper/HelperInfo.plist` 的 `SMAuthorizedClients`

修改 `project.yml` 後，以 XcodeGen 重新產生專案：

```sh
xcodegen generate \
  --spec iPhoneLocationMove/project.yml \
  --project . \
  --project-root .
```

## 首次執行

1. 閱讀並確認第三方服務條款與帳號風險提醒。
2. App 會先檢查 PATH 中是否已有功能相容的 `pymobiledevice3`。
3. 若沒有，可按「安裝裝置支援」。App 會使用現有 Python 建立自己的 venv，
   不會修改 global Python 或 Homebrew。
4. 按「核准 Helper」，完成 macOS 管理員授權。這個開發版使用
   `SMJobBless` 安裝最小權限的 tunnel helper。
5. 以 USB 連接並解鎖 iPhone；若 iPhone 詢問，選擇信任這台 Mac。
6. App 會依序檢查信任、Developer Mode、Developer Disk Image、tunnel 與
   DVT session。所有步驟完成後才會顯示裝置已就緒。

App 專用的使用者層 runtime 位於：

```text
~/Library/Application Support/iPhoneLocationMove/DeviceRuntime/
```

privileged helper 不會透過網路安裝套件。它只使用 App 內嵌、固定版本、經
code signature 與 SHA-256 trust anchor 驗證的離線 wheelhouse，並原子安裝到：

```text
/Library/Application Support/iPhoneLocationMove/TunnelRuntime/current/
```

## 使用方式

### 單點定位

1. 搜尋地點或在地圖上選擇一點。
2. 確認 preview 座標。
3. 按「設定位置」並確認風險提示。

### A／B 步行路線

1. 在地圖上指定 A、B 兩點。
2. 等待 MapKit 產生步行路線。
3. 選擇 `1–7 km/h` 的速度。
4. 視需要勾選「往返循環」。
5. 按「開始」；未勾選往返時，到達 B 後停止在 B。

執行中可暫停、繼續或調整速度。調速會以最後確認成功的位置作為新基準，
不把尚未確認的 tick 顯示成已完成進度。

## 清除模擬定位

正常情況請使用 App 內的「停止模擬」。App 會先停止位置 producer，再向 iPhone
送出 clear。真正退出 App 時也會依序 clear、關閉 DVT helper、停止 tunnel，完成後
才退出。

如果 USB 意外拔除，重新接上同一台 iPhone 後讓 App 執行 recovery；App 會先
clear 可能殘留的位置，不會自動繼續舊路線。

若 App 已異常終止且無法 recovery，可先重新啟動 App 並連接同一台 iPhone。
仍無法清除時，可手動建立 `pymobiledevice3` tunnel，再執行：

```sh
pymobiledevice3 developer dvt simulate-location clear \
  --rsd <TUNNEL_ADDRESS> <TUNNEL_PORT>
```

在 clear 成功前，不應假設 iPhone 已恢復真實定位。

## 測試

macOS unit／integration tests：

```sh
xcodebuild test \
  -project iPhoneLocationMove.xcodeproj \
  -scheme iPhoneLocationMove \
  -destination 'platform=macOS'
```

Python DVT protocol tests：

```sh
python3 -m unittest discover -s iPhoneLocationMoveHelper/tests
```

這些自動化測試不需要實體 iPhone 或 root 權限。

## 故障排除

### 找不到 Python

安裝 Python 3.9+，或確認 `python3` 位於 PATH、`/opt/homebrew/bin/python3`、
`/usr/local/bin/python3` 或 `/usr/bin/python3`。App 不會自行安裝 system Python。

### 裝置支援安裝不完整

按「重試」。安裝採 staging 後才 publish；取消或失敗的 staging 不會被當成可用
runtime。必要時可移除 App 專用 runtime 後重建：

```sh
rm -rf "$HOME/Library/Application Support/iPhoneLocationMove/DeviceRuntime"
```

### 找不到 iPhone

- 使用可傳輸資料的 USB 線。
- 解鎖 iPhone。
- 確認 iPhone 已信任這台 Mac。
- 只支援 USB，不支援 Wi-Fi discovery。

### Developer Mode 或 Developer Disk Image 失敗

確認 iPhone 已啟用 Developer Mode，Xcode 支援該 iOS 版本，然後保持手機解鎖並
重試。App 不會略過 prerequisite 或在前一步失敗後繼續建立 tunnel。

### Helper 授權失敗

確認 App 與內嵌 helper 都由同一個 Team 簽署，且上述三處 Team ID 已同步。拒絕
管理員授權不會讓 App 誤報 ready，可再次按「核准 Helper」重試。

## 移除 privileged helper

先退出 App並確認沒有進行中的模擬，再執行：

```sh
sudo launchctl bootout system/com.cash.iPhoneLocationMoveTunnelHelper
sudo rm -f /Library/PrivilegedHelperTools/com.cash.iPhoneLocationMoveTunnelHelper
sudo rm -f /Library/LaunchDaemons/com.cash.iPhoneLocationMoveTunnelHelper.plist
sudo rm -rf "/Library/Application Support/iPhoneLocationMove"
```

`launchctl bootout` 在 helper 未載入時可能回報找不到 service；其餘固定路徑仍可
逐項確認與移除。移除後重新從 Xcode Run，首次建立 tunnel 時會再次要求管理員
授權。

## 授權與公開發佈

內嵌的 `pymobiledevice3 9.36.3` package metadata 宣告
`GPL-3.0-or-later`。目前專案只供本機開發使用；若要提供其他人下載，發佈前至少
需要：

- 完成 GPL-3.0-or-later 與所有 transitive dependencies 的授權、notice、源碼提供
  與再散布方式審查。
- 決定專案本身的授權並加入完整 license 文件。
- 使用 Developer ID，完成 hardened runtime、簽章與公證流程。
- 重新評估 deprecated `SMJobBless`，並依正式發佈模型考慮遷移至
  `SMAppService`。
- 執行 privileged helper security review、雙架構 runtime 建置與實體裝置
  acceptance。

使用定位模擬可能違反第三方服務條款，或導致帳號限制。這個專案不提供反偵測、
規避反作弊或帳號安全保證。
