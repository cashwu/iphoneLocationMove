# iPhone Location Move

以原生 SwiftUI 與 MapKit 製作的 macOS 定位模擬工具。透過 USB 控制一台
iOS 17+ iPhone，可設定單一位置，或沿 MapKit 步行路線在 A、B 兩點間移動。
路線支援 `1–7 km/h`、暫停、繼續，以及選用的往返循環。

底層使用 [`pymobiledevice3`](https://github.com/doronz88/pymobiledevice3) 的
developer DVT `simulate-location` 功能——這是 Apple 提供給開發者測試定位相關
App 的正式機制，與 Xcode 的 location simulation 相同層級，不涉及越獄或修改
iPhone 系統。

> **⚠️ 使用前請務必閱讀下方[免責聲明](#免責聲明)。**

## 免責聲明

本專案**僅供軟體開發、測試與教育研究用途**。使用本工具即表示你已閱讀、
理解並同意以下條款：

- **服務條款風險**：在第三方 App 或服務（地圖、社群、遊戲、簽到、外送等）
  中使用模擬定位，可能違反其服務條款，並可能導致警告、功能限制、
  暫時或永久停權。相關風險完全由使用者自行承擔。
- **法律責任**：使用者有責任確保自己的使用方式符合所在地區的法律法規。
  請勿將本工具用於任何詐欺、規避執法、侵害他人權益或其他非法用途。
- **不提供規避能力**：本專案不提供、也不會提供任何反偵測、規避反作弊
  或帳號安全保證。
- **裝置與系統風險**：本工具需要 macOS 管理員權限安裝 privileged helper，
  並透過開發者通道與 iPhone 通訊。作者已盡力將權限最小化，但無法保證
  在所有環境下都不會發生非預期行為。模擬結束後，請依「[清除模擬定位](#清除模擬定位)」
  章節確認 iPhone 已恢復真實定位。
- **不提供任何擔保**：本軟體按「現狀（AS IS）」提供，不附帶任何明示或
  默示的擔保，包括但不限於適售性、特定用途適用性與不侵權。在任何情況下，
  作者與貢獻者均不對因使用或無法使用本軟體所生的任何直接、間接、附帶、
  衍生性損害（包括帳號損失、資料損失或裝置問題）負責。

### Disclaimer (English)

This project is intended **for software development, testing, and educational
purposes only**. By using this tool, you acknowledge and agree that:

- Simulating your location in third-party apps or services may violate their
  Terms of Service and may result in warnings, restrictions, or permanent
  account bans. You assume all such risks.
- You are solely responsible for complying with all applicable laws and
  regulations in your jurisdiction. Do not use this tool for fraud, evading
  law enforcement, infringing on others' rights, or any other unlawful purpose.
- This project does not provide any anti-detection, anti-cheat evasion, or
  account-safety guarantees.
- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED. IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE FOR ANY
  CLAIM, DAMAGES, OR OTHER LIABILITY ARISING FROM THE USE OF THIS SOFTWARE.

## 功能特色

- 原生 SwiftUI + MapKit 介面，支援地點搜尋與地圖選點。
- 單點定位：搜尋或點選地圖，確認後送出模擬位置。
- A／B 步行路線：由 MapKit 產生真實步行路線，以 `1–7 km/h` 沿路線移動，
  支援暫停、繼續、調速與往返循環。
- 安全的清除流程：停止模擬、App 退出與 USB 拔除 recovery 都會先向 iPhone
  送出 clear，避免殘留模擬位置。
- 最小權限 privileged helper：只使用 App 內嵌、固定版本、經 code signature
  與 SHA-256 trust anchor 驗證的離線 wheelhouse，不透過網路安裝套件。

## 環境需求

執行 App：

- macOS 13+
- Apple Silicon Mac（目前內嵌的 privileged tunnel wheelhouse 是 arm64）
- iOS 17+ iPhone
- 可傳輸資料的 USB 線
- iPhone 已解鎖、信任這台 Mac，且已開啟 Developer Mode
- Python 3.9+，或 PATH 中已有功能相容的 `pymobiledevice3`

從原始碼建置另需：

- Xcode，且已登入可用的 Apple Development 帳號

開啟 Developer Mode：

1. 在 iPhone 前往「設定 → 隱私權與安全性 → 開發者模式」。
2. 開啟後依提示重新啟動 iPhone。
3. 重新解鎖並確認啟用。

## 下載安裝

最新版本可從 [Releases](https://github.com/cashwu/iphoneLocationMove/releases/latest)
取得 `iPhoneLocationMove-<version>.dmg`。

1. 下載並開啟 DMG，把 `iPhoneLocationMove.app` 拖到「應用程式」。
2. 這個 DMG 以 **Apple Development 憑證簽署，未經 Apple 公證（notarization）**，
   從瀏覽器下載後會被 Gatekeeper 擋下。首次執行前需自行移除 quarantine 屬性：

   ```sh
   xattr -dr com.apple.quarantine /Applications/iPhoneLocationMove.app
   ```

3. 開啟 App，依「[首次執行](#首次執行)」完成裝置支援安裝與 helper 授權。

> **⚠️ 關於預先建置的 DMG**
>
> - 未公證代表 macOS 不會替你驗證這個安裝檔的來源與完整性；你必須自行確認
>   DMG 確實來自本 repo 的 Releases 頁面。移除 quarantine 等於跳過 macOS 的
>   來源檢查，請只對你自己確認過來源的檔案這樣做。
> - 這個 build 帶有 `com.apple.security.get-task-allow`（開發用 entitlement），
>   並非適合大規模散布的正式版本。
> - App 會安裝一個以 root 執行的 privileged helper。安裝前請先閱讀
>   [免責聲明](#免責聲明)並自行評估風險。
> - 若不接受以上限制，請改用「[從 Xcode 建置與執行](#從-xcode-建置與執行)」，
>   以你自己的 Apple Development Team 簽署後執行。

## 從 Xcode 建置與執行

本專案以 Apple Development 憑證從本機 Xcode Build／Run。Fork 或 clone 後，
你需要改用**自己的** Development Team：

1. 開啟 `iPhoneLocationMove.xcodeproj`。
2. Scheme 選擇 `iPhoneLocationMove`，Destination 選擇 `My Mac`。
3. 在 Signing & Capabilities 換成你自己的 Team。
4. 同步更新以下三處的 Team ID（App 與 privileged helper 透過
   `SMJobBless` 互相驗證簽章，三處必須一致）：
   - `iPhoneLocationMove/project.yml` 的 `DEVELOPMENT_TEAM`
   - `iPhoneLocationMove/Info.plist` 的 `SMPrivilegedExecutables`
   - `iPhoneLocationMoveTunnelHelper/HelperInfo.plist` 的 `SMAuthorizedClients`
5. 修改 `project.yml` 後，以 XcodeGen 重新產生專案：

   ```sh
   xcodegen generate \
     --spec iPhoneLocationMove/project.yml \
     --project . \
     --project-root .
   ```

6. 按 Run（`⌘R`）。

## 首次執行

1. 閱讀並確認第三方服務條款與帳號風險提醒。
2. App 會先檢查 PATH 中是否已有功能相容的 `pymobiledevice3`。
3. 若沒有，可按「安裝裝置支援」。App 會使用現有 Python 建立自己的 venv，
   不會修改 global Python 或 Homebrew。
4. 按「核准 Helper」，完成 macOS 管理員授權。目前使用 `SMJobBless` 安裝
   最小權限的 tunnel helper。
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

## 本機 Release 打包

`Scripts/package-app.sh` 提供可從任意 current directory 執行的本機打包入口。
執行前需要：

- 已安裝 Xcode command line tools。
- Xcode 已登入你在上方設定的同一個 Apple Development Team。
- PATH 中有 `python3`，可執行上述 Python protocol tests。

從 repository root 執行預設流程：

```sh
Scripts/package-app.sh
```

腳本會依序清理 `build/`、執行 Xcode tests、執行 Python tests、建置 Release
App、驗證 App 與 embedded helper 的簽章及雙向 `SMJobBless` requirements，最後
建立 DMG。任一必要階段失敗時會停止且不宣告完成。

可用選項：

- `-h`／`--help`：顯示說明。
- `-v VER`／`--version VER`：覆寫該次 App 的 `CFBundleShortVersionString`，
  並建立版本化 DMG，例如 `--version 1.2.3`。
- `--no-clean`：保留既有 `build/` 與 derived data。
- `--skip-tests`：明確跳過 Xcode 與 Python tests。
- `--no-dmg`：只產生並驗證 `.app`。

產物位於：

```text
build/Export/iPhoneLocationMove.app
build/iPhoneLocationMove.dmg
build/iPhoneLocationMove-<version>.dmg
```

這些產物保留 Apple Development 簽署，只供已設定相同 Team 的本機開發與驗證。
腳本不會改成 ad-hoc signing，也不會產生已公證（notarized）、適合直接散布給
一般使用者的版本。目前 [Releases](https://github.com/cashwu/iphoneLocationMove/releases)
上的 DMG 即由此腳本產生，因此屬於未公證版本，安裝方式與限制見
「[下載安裝](#下載安裝)」。若要正式對外發佈安裝檔，仍須完成 Developer ID、hardened
runtime、公證流程與 privileged helper security review。

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

確認 App 與內嵌 helper 都由同一個 Team 簽署，且「從 Xcode 建置與執行」章節
列出的三處 Team ID 已同步。拒絕管理員授權不會讓 App 誤報 ready，可再次按
「核准 Helper」重試。

## 移除 privileged helper

先退出 App 並確認沒有進行中的模擬，再執行：

```sh
sudo launchctl bootout system/com.cash.iPhoneLocationMoveTunnelHelper
sudo rm -f /Library/PrivilegedHelperTools/com.cash.iPhoneLocationMoveTunnelHelper
sudo rm -f /Library/LaunchDaemons/com.cash.iPhoneLocationMoveTunnelHelper.plist
sudo rm -rf "/Library/Application Support/iPhoneLocationMove"
```

`launchctl bootout` 在 helper 未載入時可能回報找不到 service；其餘固定路徑仍可
逐項確認與移除。移除後重新從 Xcode Run，首次建立 tunnel 時會再次要求管理員
授權。

## 授權（License）

本專案以 **GPL-3.0-or-later** 授權，全文見 [`LICENSE`](LICENSE)。

repo 內嵌的 `pymobiledevice3 9.36.3` 離線 wheelhouse（位於
`iPhoneLocationMoveTunnelHelper/Resources/tunnel-wheelhouse/`）依其 package
metadata 宣告為 `GPL-3.0-or-later`，其餘 wheel 各自保留原授權。再散布本專案
（含原始碼或編譯後產物）時，必須同時滿足 GPL-3.0-or-later 與各內嵌元件的
授權、notice 與源碼提供要求。

若要散布編譯後的安裝檔（而非僅公開原始碼），發佈者另需自行完成：

- GPL-3.0-or-later 與所有 transitive dependencies 的授權與再散布審查。
- Developer ID 簽署、hardened runtime 與公證（notarization）。
- 重新評估 deprecated 的 `SMJobBless`，並考慮遷移至 `SMAppService`。
- privileged helper security review、雙架構 runtime 建置與實體裝置 acceptance。
