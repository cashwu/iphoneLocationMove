# Acceptance Results

## 2026-07-27 — Task 7.3 privileged-helper acceptance

狀態：完成。所有 production cases 均透過原始 signed Debug App、實際
`SMJobBless` helper、production XPC connection 與 root-owned runtime 執行；
deterministic tests只作 race window與錯誤分支的補充證據。

### Production 安裝與 caller trust

- 新版 embedded helper 與
  `/Library/PrivilegedHelperTools/com.cash.iPhoneLocationMoveTunnelHelper`
  SHA-256 均為
  `ca5ee4c5a5eb30be70206afe8c449cfbc50f87860524fef0fb8a2d298d76d8ac`。
- installed helper 為 `root:wheel`、mode `0544`；LaunchDaemon plist 為
  `root:wheel`、mode `0644`。
- helper identifier 為 `com.cash.iPhoneLocationMoveTunnelHelper`，Team ID 為
  `2LRM76M575`，Apple Development signature通過。
- runtime current 為 root-owned、mode `0700`；`runtime-seal.json` 為
  root-owned、mode `0600`，seal含 6869 個排序後 generated file entries。
- 原始 signed App 可取得 production XPC lease；修改 executable 後的
  signature-invalid App copy與 ad-hoc re-signed Team-ID-mismatch App copy均由
  listener拒絕，runner收到 `tunnel-failure`且未建立 lease。原始 helper的
  designated requirement／Team ID正向案例與兩個負向 caller fixtures共同驗證
  production caller trust；invalid PID／UID／audit-session與 stale
  `connectionID`另由 deterministic identity tests驗證。

### Production lease、cleanup 與 startup reconcile

- `positive-start` 完成 start／status／stop。
- `pending-duplicate` 的兩個 concurrent requests 回傳相同 lease ID，未建立第二個
  root tunnel process。
- `lost-reply-retry` 以相同 idempotency key取回相同 lease ID。
- `connection-invalidation` 與 `app-termination` 均在 owner loss 後把 tunnel
  process count降回 0；其後 `startup-reconcile` 成功。
- startup reconcile先於 adapter start；reconcile failure阻止 start／DVT／ready。
- endpoint-timeout 使用固定 root-owned、mode `0700` executable與重新產生的
  root-owned、mode `0600` seal；production runner在 15 秒回傳
  `{"case":"endpoint-timeout","detail":"timeout","errorCode":"timeout","passed":true}`，
  after snapshot只有 launchd helper，沒有 fixture或 tunnel process。

### Production runtime seal tamper

每個案例只修改 root-owned current runtime的一個條件，runner均回傳
`passed: true`與 typed `tunnel-failure`，且未建立 tunnel process：

- missing／extra：`Generated runtime file set does not match its seal.`；
- symlink：`Generated runtime metadata mismatch: runtime/pymobiledevice3`；
- generated file owner／mode：`Generated runtime metadata mismatch`；
- generated file digest：完整 seal equality檢查拒絕內容差異；
- seal owner／mode：`Runtime file owner or mode mismatch`。

production acceptance另發現 Python啟動會寫入 bytecode cache、使 sealed runtime在
下一次 start自我失效。已在 root tunnel process environment固定
`PYTHONDONTWRITEBYTECODE=1`並新增回歸測試；重新安裝 helper後連續兩次
production start均通過 seal驗證，兩次只因固定不存在的 negative-case device ID
回傳 process early-exit，不再出現 file-set mismatch。

### Deterministic 補充驗證

執行：

```sh
xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS' -only-testing:iPhoneLocationMoveTests/TunnelHelperContractTests -only-testing:iPhoneLocationMoveTests/TunnelXPCInterfaceTests
```

結果為 `TEST SUCCEEDED`。測試涵蓋：

- invalid caller signature、designated requirement 與 Team ID fail closed；
- device ID、caller ownership、unknown lease 與 idempotent start；
- 相同 idempotency key 不建立第二個 tunnel，並支援 start reply 遺失後以相同 key 取得既有 lease；
- endpoint parse、process early exit、stop failure 與 exited lease cleanup；
- XPC owner invalidation、App crash 等價 owner loss 與 reconcile 回收；
- symlink、owner、mode、digest tamper fail closed；
- payload 與外部 manifest 同時替換時由 embedded digest trust anchor 拒絕；
- offline wheelhouse、root-owned staging、generated runtime seal與 atomic publish；
- endpoint deadline的可控制 clock、attach前／pending／轉 active前 invalidation race，
  以及所有 external I/O期間 condition lock可取得。

### Uninstall／cleanup

最後透過 macOS 管理員授權執行固定路徑 cleanup，並確認：

- privileged helper executable 已移除；
- LaunchDaemon plist 已移除；
- root-owned `iPhoneLocationMove` Application Support runtime 已移除；
- `launchctl` system domain 已無 `com.cash.iPhoneLocationMoveTunnelHelper`；
- process scan 已無 `iPhoneLocationMoveTunnelHelper`、privileged `pymobiledevice3 remote tunnel` 或 `TunnelRuntime` process。

## 2026-07-27 — Task 7.4 physical-device acceptance

使用者明確確認 task 7.4 的實機驗收視為完成。驗收裝置為 `Emily iPhone 14 Pro`、iOS `26.5.2`、USB 連線。

持久化 diagnostic log 可獨立確認：

- runtime probe、helper approval、USB discovery、prerequisite preparation 與 session ready；
- route 以 `4.5 km/h`、`roundTrip: true` 啟動；
- 13:35:35 至 13:44:37 共 526 次 `location.set_requested` 與 526 次 `location.set_succeeded`，0 次 set failure；
- stop 後 `location.clear_succeeded`；
- ready-without-active quit 最後完成 `teardown.completed`。

單點、`900 m` 單程、端點折返、pause/resume、執行中調速、active quit clear、USB 拔除／重連與拒絕授權，依使用者本次明確 acceptance sign-off 視為通過；現有 diagnostic log 不足以逐項獨立辨識這些 UI 操作，因此不將它們描述成 log-verified。

## 2026-07-27 — Task 7.6 validation and scope review

狀態：完成。

- `cash validate add-macos-location-simulator`：通過。
- `cash analyze add-macos-location-simulator --json`：Coverage、Consistency、Gaps 均為
  Clean；71 項 Ambiguity finding全為缺少額外 `##### Example:` 的 Suggestion。
- implementation source只位於 proposal `## Impact` 宣告的
  `iPhoneLocationMove.xcodeproj/`、`iPhoneLocationMove/`、
  `iPhoneLocationMoveHelper/`、`iPhoneLocationMoveTunnelHelper/`、
  `iPhoneLocationMoveTests/` 與 `README.md`；change artifacts與 Cash signals屬
  workflow metadata，不是新增 product target。
- 尚未 archive的新 capability以
  `openspec/changes/add-macos-location-simulator/specs/` 下的 delta為
  source-of-truth；`ios-device-session` 37 個 scenarios與
  `location-simulation` 36 個 scenarios均由 task、deterministic test或本文件的
  production／physical-device acceptance覆蓋，analyzer Coverage為 Clean。
- 未加入 Wi-Fi、多裝置並行、隨機位置、公開發佈版內建 Python runtime或反偵測
  功能；README明確維持 USB-only與不提供反偵測保證。root-owned offline tunnel
  runtime只服務必要的 privileged boundary，符合 proposal與design明確允許的
  scope。
