# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

（無）

### Warning

- severity: Warning｜confidence: 90｜layer: design｜reviewer: B
  - location: `iPhoneLocationMoveTunnelHelper/Acceptance/PRODUCTION_ACCEPTANCE.md:68`、`:183`；proposal `## Impact`
  - summary: 手冊的 process snapshot／uninstall 清理 `pgrep` pattern 為 `pymobiledevice3.*remote.*tunnel`，改用 `lockdown start-tunnel` 後過時，且該檔未列入 Impact。
  - recommendation: 將手冊加入 Impact 與 task 1.2 delivery，pattern 同步為 runner 使用的 `pymobiledevice3.*start-tunnel`。
  - 主 agent 核實：兩行確實存在；child argv 含 `TunnelRuntime` 路徑時仍會命中，因此實際假陰性風險較低，但文件過期與 Impact 遺漏屬實。

### Suggestion

- Reviewer A #1（confidence 60，降級）：design Risks 未涵蓋 macOS 27 + iOS 17.0–26.x 改走 lockdown `CoreDeviceProxy` 的支援矩陣變化（signal `host-support-matrix-transport-regression`）。
- Reviewer A #2（confidence 75，降級）：既有 `TunnelHelperContractTests` 的 verified UID oracle、fake launcher `targetUserID` 簽章與 `native-launch` case 無法原樣通過，design 未列出。
- Reviewer A #3（confidence 60，降級）：`RuntimeManagerTests` 的 `testMacOS27RejectsClassicOnlyTunnelCapability` 等既有斷言與新行為衝突，未列出須改寫的測試。
- Reviewer A #4／B #5（confidence 50，降級；合併）：task 1.2 red 若使用最終 API 會依測試機 OS 而非 deterministic，或先編譯失敗。
- Reviewer A #5（confidence 50，降級；與 B Warning 同一位置，已合併處理）。
- Reviewer B #3（confidence 50，降級）：measured 以 `sudo` 執行，environment 與 helper 不同；未寫明依賴 system usbmux pair record。
- Reviewer B #4（confidence 50，降級）：macOS 27+ device access 邊界語意變化未於 Decision 2 說明。

（Reviewer B #2，confidence 40：#1994 驅逐對 lockdown 長連線的適用性未驗證 — 低於 50 已剔除，但仍於 Fix Actions 補充 Risk 與驗收條件。）

## Rating

- 累積 blocking set Critical 數：0
- 累積 blocking set Warning 數：1
- non-blocking triaged finding 數：7
- critical_gap: false
- round_type: full
- rationale: 本輪為 unseeded 第一輪，所有通過 filter 的 Critical／Warning 皆為 blocking；Reviewer B 的 acceptance 手冊 pattern 過期（confidence 90）留存為 Warning，因此不能 pass，進入 next_round。

## Fix Actions

- 修正 blocking Warning（B #1）：`proposal.md` Impact Modified 加入 `iPhoneLocationMoveTunnelHelper/Acceptance/PRODUCTION_ACCEPTANCE.md`，Proposed Solution 加入 pattern 同步；`tasks.md` 1.2 delivery 加入該檔並描述 pattern 改為 `pymobiledevice3.*start-tunnel`。
- Suggestion A #1 與 B #2 處理：`design.md` Risks 新增 macOS 27 + iOS 17.0–26.x 走 lockdown 未實測（iOS 17.0–17.3 可能 fail closed，與 macOS 13–26 一致）與 #1994 驅逐適用性未觀察兩項；`tasks.md` 1.3 success 加入 route simulation 連續至少 3 分鐘未中斷。
- Suggestion A #2／A #3 處理：`design.md` Decision 5 列出須改寫或移除的既有 `RuntimeManagerTests` 與 `TunnelHelperContractTests` 斷言、fake 簽章與 case 名稱。
- Suggestion A #4／B #5 處理：`design.md` Decision 5 與 `tasks.md` 1.1／1.2 red 改為沿用既有 host-version seam（27）建構，使 red deterministic。
- Suggestion B #3 處理：`design.md` Context measured #3 補充 `sudo` environment 與 helper environment 差異及 system pair record 假設，以 task 1.3 作為實證。
- Suggestion B #4 處理：`design.md` Decision 2 補充 device access 邊界回到 system usbmux pair record 模型。
- 修改檔案：`openspec/changes/fix-ios-27-2-classic-tunnel/proposal.md`、`openspec/changes/fix-ios-27-2-classic-tunnel/design.md`、`openspec/changes/fix-ios-27-2-classic-tunnel/tasks.md`。
- Post-fix mechanical self-check：無 annotation、MODIFIED／REMOVED 標題與 master 逐字相同、`pymobiledevice3.*start-tunnel`、`TunnelHostPolicy`、`targetUserID`、`hostOperatingSystemVersion` 在各 artifact 拼寫一致；無新增計數宣稱失配。`validate` 通過、`analyze` 無 Critical／Warning。
- 非 blocking `new` triage：上述 7 項 Suggestion 均已處理，不另開 follow-up。

## Decision

next_round
