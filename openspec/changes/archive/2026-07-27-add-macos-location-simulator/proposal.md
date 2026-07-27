## Summary

建立原生 macOS App，讓使用者透過 USB 控制一台 iOS 17+ iPhone 的模擬定位。App 提供彼此獨立的單點定位與 A/B 步行路線兩種模式，並管理 `pymobiledevice3` 能力檢查、iOS tunnel、長時間 DVT session、斷線恢復與安全清除。

完成 privileged boundary 時，系統也必須讓尚在等待 RSD endpoint 的 tunnel process 立即受到 caller ownership 管理、在 App 新 session 啟動前回收 stale lease，並以可重現的 production XPC acceptance 證明負向安全案例，而不是只依賴 fake harness。

## Motivation

目前使用者必須在終端機手動建立 tunnel、輸入座標並維持定位程序，無法從地圖直接選點，也沒有可暫停、調速或往返的步行路線。這使日常使用容易誤輸座標、遺留模擬狀態，且無法清楚掌握裝置、路線與 session 狀態。

這是一項全新 Feature。第一版以單一使用者、單一 USB iPhone 與已驗證的 iOS 17+ 環境為中心，優先建立清楚且可恢復的操作流程，同時保留未來公開發佈時改用內建 Python runtime 的空間。

Cash Apply Round 1 進一步發現，原本 task 7.3 的正向實機 smoke test 加上 user-space contract tests，仍無法證明 production helper 在 endpoint 無回應、App crash、stale lease、非法 caller 與生成 runtime 遭竄改時會 fail closed。這些缺口必須回填到同一 change，完成後才可宣告 privileged acceptance 通過。

## Proposed Solution

- 使用原生 `SwiftUI + MapKit` 顯示地圖、搜尋地點或地址、預覽標記並規劃步行路線。
- 單點定位模式在使用者明確確認後設定 iPhone 位置，持續到使用者停止模擬或退出 App。
- 步行路線模式讓使用者選擇 A、B，沿 MapKit 步行 polyline 以預設 `4.5 km/h` 移動；速度可在 `1–7 km/h` 內調整，支援暫停、繼續及選用的往返循環。
- 以 `RouteSession` 管理路線進度與狀態，以單一 `PymobiledeviceAdapter` 隔離 Swift UI 與 Python／process 細節；adapter 內的長時間 Python helper 持有 DVT session。route update 採最多一個 in-flight command 與 latest-only coalescing，pause、replacement 及 clear 以 epoch barrier 阻擋舊更新。
- tunnel 由權限受限、只接受固定操作的 privileged helper 啟停；helper 以綁定 caller 與 device 的唯一 lease 管理 process，並只從通過 App code signature／designated requirement／Team ID、signed-helper embedded digest manifest、owner、mode、symlink 與 atomic-install 驗證的 root-owned offline payload 啟動。
- tunnel process 一建立就進入 `PendingTunnelStart` ownership；endpoint handshake 最長等待 15 秒，同一 caller／device／idempotency key 的重複 start 共用同一 pending result。timeout、XPC invalidation、caller death 或 parse failure都必須回收尚未形成 active lease 的 process。
- App 每次 production device preparation 在 start tunnel 前先呼叫 `reconcile()`；failure 阻止新 tunnel 與 ready state。
- caller trust 使用 Apple 公開的 `NSXPCConnection` process／effective-user／audit-session security attributes，在 listener accept 階段完成 code-signature／designated requirement／Team ID 驗證，並把後續 request綁定到該connection-specific exported service；不宣稱取得公開API未提供的raw audit token。
- embedded trust anchor固定offline wheelhouse與build plan；helper在root-owned private staging生成runtime後建立sealed digest manifest，atomic publish，並在每次start前拒絕任何missing／extra檔案、symlink、owner／mode或digest mismatch。
- DEBUG build提供只接受固定案例enum的production XPC acceptance runner，用實際signed App／SMJobBless helper驗證合法與非法caller、重複start、lost reply、pending-start invalidation、startup reconcile、runtime tamper及uninstall cleanup；runner不得接受任意command、path或argument list。
- App 啟動時優先使用相容的既有 `pymobiledevice3`；找不到時，可用現有 Python 一鍵建立 App 專用 venv。若沒有相容 Python，顯示可執行的安裝指引。
- 第一版僅支援 USB 與單一活動裝置；偵測到多台時讓使用者選擇一台，不並行控制。
- 真正退出 App 前要求確認並清除模擬定位；USB 意外中斷時進入中斷狀態，重新連線後先清除可能殘留的模擬狀態。
- 在首次使用與開始模擬前顯示用途及第三方服務條款風險提醒，不宣稱能規避偵測或保證帳號安全。

## Non-Goals

- Wi-Fi 裝置連線或 Wi-Fi 裝置發現。
- 同時控制多台 iPhone。
- 自動產生隨機位置、地理圍欄或遊戲自動化。
- 內建 Python runtime、Mac App Store 發佈、自動更新、公開下載包裝或正式 GPL-3.0 發佈評估。
- 防禦已取得 root 權限、可同時替換helper executable與root-owned seal的攻擊者；本change的runtime integrity boundary防止一般使用者或被竄改caller修改privileged execution內容。
- 與另一個既有的 `iphoneLocation` repository 共用程式碼、資料、preset 或設計。
- 繞過第三方服務的反作弊、裝置檢查或帳號處分。

## Alternatives Considered

- **只包裝 `pymobiledevice3` CLI 的 GPX 播放**：能依 GPX timestamp 前進，但不提供所需的可靠暫停與無限往返；無法完整承擔路線 session contract。
- **每秒啟動一次 CLI 設定座標**：process 與 DVT session churn 過高，錯誤與清理邊界不清楚，因此不採用。
- **Tauri、Electron 或 Web 地圖**：會為原生 macOS 單平台需求增加額外 runtime 與 bridge，MapKit 已能直接提供地圖搜尋與步行路線，因此不採用。
- **第一版直接內建 Python runtime**：會提前引入體積、雙架構、簽署、公證與安全更新成本；延後至公開發佈階段。
- **由 root process 直接執行網路 `pip` 或 user-writable Python／package**：會把下載或路徑替換變成 root code execution 邊界，因此禁止；privileged tunnel runtime 只接受 App signature 與 signed helper 內嵌 trust anchor 驗證過、離線、hash-locked 且原子安裝的 payload。

## Capabilities

### New Capabilities

- `ios-device-session`：偵測並選擇 USB iPhone、檢查 prerequisite、準備 `pymobiledevice3`、管理 tunnel／DVT session，以及處理退出、斷線與恢復。
- `location-simulation`：在 MapKit 上搜尋與選點，明確設定單點定位，或執行可調速、暫停、繼續與往返的 A/B 步行路線。

### Modified Capabilities

- (none)

## Impact

- Affected specs:
  - New: `openspec/specs/ios-device-session/spec.md`
  - New: `openspec/specs/location-simulation/spec.md`
- Affected code:
  - New:
    - `iPhoneLocationMove.xcodeproj/`
    - `iPhoneLocationMove/`
    - `iPhoneLocationMoveHelper/`
    - `iPhoneLocationMoveTunnelHelper/`
    - `iPhoneLocationMoveTests/`
    - `README.md`
  - Modified:
    - (none)
  - Removed:
    - (none)
