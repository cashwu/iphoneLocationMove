# Cash Propose Review — Round 3

## Reviewer Findings

### Cumulative blocking set 判定（Reviewer V）

- round 2 移除的兩個 Critical 均未回退：Decision 2 的分流未削弱「session 清空 → 後續回 `usbDisconnected`、最多一個 lease」；MODIFIED「模擬模式互斥與安全取代」「單點定位模式」未被 round 2 動到。

### Critical

（無）

### Warning

- severity: Warning；confidence: 95；layer: text；location: specs/location-simulation MODIFIED「工作區重置」 vs master 約 657-661 行；summary: delta 漏抄 master 最後一個 scenario「重置後的鏡頭行為」，archive 時會靜默刪除該 scenario；recommendation: 逐字補回並以段落 diff 自檢；reviewer source: Reviewer V Finding 1；disposition: `fix-introduced`；introduced_by: r2 Fix Action「已過濾項目順帶處理」（新增 MODIFIED「工作區重置」）

### Suggestion

- severity: Suggestion；confidence: 60；layer: text；location: specs/ios-device-session requirement 正文、proposal.md Proposed Solution 第 1 點、design.md Risks「reconnect 內 clear 失敗」；summary: round 2 的 clear 失敗分流只傳播到細節層，三處摘要仍是「一律拆除、一律 cleanupPending」；recommendation: 加限定語；reviewer source: Reviewer V Finding 2；disposition: `fix-introduced`；introduced_by: r2 Fix Action「fix-introduced（reconnect 內再次拔線）」

### 已過濾（confidence < 50，僅記錄）

- （45）Decision 2 以 `usbDisconnected` error identity 作為「已被 markUSBDisconnected 清空」判準；正式路徑下該假設成立，不構成 finding。

### round 2 Fix Actions 驗證結果

1 proposal 殘留：通過；2 clear 失敗分流：文件同步通過、程式碼路徑對照無 stale 資源與第二 lease；3 `[P]`：通過；4「terminal helper或tunnel failure」：通過；5 MODIFIED「工作區重置」逐字比對：不通過（Finding 1）；6 fix-introduced 矛盾掃描：通過。

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 1
- non-blocking triaged finding count: 1
- critical_gap: false
- round_type: micro
- rationale: Reviewer V 回報一個 confidence 95 的 `fix-introduced` Warning（MODIFIED requirement 漏抄 master scenario），依規則進入 cumulative blocking set，必須修正並由下一輪驗證；另一個 fix-introduced 為 confidence 60 的 Suggestion，非 blocking。依位置規則，下一輪為本 run 的第四輪，MUST 為 full round。

## Fix Actions

- **Warning（漏抄 scenario）**：以程式自 master 擷取「工作區重置」整段（含「重置後的鏡頭行為」scenario）取代 delta 尾段，只在兩處 busy 枚舉加入 `reconnecting`；段落 diff 確認只剩該兩處差異，scenario 數 master／delta 皆為 7。修改檔案：specs/location-simulation/spec.md。
- **Suggestion（摘要層未分流）**：specs/ios-device-session/spec.md requirement 正文、proposal.md Proposed Solution 第 1 點、design.md Risks「reconnect 內 clear 失敗」三處加入 `usbDisconnected` 與其他 failure 的分流限定語。修改檔案：specs/ios-device-session/spec.md、proposal.md、design.md。
- 修正後重新執行 `validate`：通過。修正後機械自檢：註解配對 0／0；七個 MODIFIED 標題逐字存在於 master；新增「MODIFIED 段落 diff」自檢，對全部七個 MODIFIED requirement 比對 master，確認每個 MODIFIED 的 scenario 數量不少於 master，且所有與 master 不同的行都是本 change 刻意修改的 requirement 正文或 WHEN 行，沒有整段 scenario 遺漏。
- 修改檔案（4）：specs/location-simulation/spec.md、specs/ios-device-session/spec.md、proposal.md、design.md。change 目錄外無修改，不呼叫 touched record。

## Decision

next_round
