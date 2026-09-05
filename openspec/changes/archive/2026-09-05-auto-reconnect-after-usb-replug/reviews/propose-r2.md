# Cash Propose Review — Round 2

## Reviewer Findings

### Cumulative blocking set 判定（Reviewer V）

- Critical 1「reconnect clear 失敗死局」：**resolved**。證據：design Decision 2 的 clear 失敗分支、ios-device-session delta 三條 AND、tasks 1.1／1.2／2.2；對照 `PymobiledeviceAdapter.reconnect()` 與 `clearLocation` 的 `guard let session` 確認 session 清空後回 `usbDisconnected`、`DeviceSessionState.cleanupPending` 存在、`prepareSession` DVT 失敗會自行 stopTunnel 故 lease 不累積。verified-resolution removal：fix reference r1「Critical 1」，verifying reviewer Reviewer V。
- Critical 2「ADDED 與 master 矛盾」：**resolved**。證據：MODIFIED「模擬模式互斥與安全取代」「單點定位模式」標題與首句逐字承接，四個 scenario WHEN 加入例外，新增「已中斷的舊 session 被新模式取代」；與「系統睡眠與裝置中斷不造成位置跳躍」不衝突（新 `SimulationSessionID`，非 resume）。verified-resolution removal：fix reference r1「Critical 2」，verifying reviewer Reviewer V。

### Critical

（無）

### Warning

（post-filter 無 blocking Warning）

### Suggestion／非 blocking

- severity: Warning（非 blocking）；confidence: 90；layer: text；location: proposal.md Proposed Solution 第 4 點；summary: 仍寫「持有 cleanup ownership」，與 design Decision 4 及 spec「不持有 cleanup ownership、不顯示停止按鈕」相反；recommendation: 改寫；reviewer source: Reviewer V Finding 1；disposition: reviewer 標記 `unresolved-prior`，主 agent 校正為 `new`——它對應的 round 1 finding 是非 blocking 的 Suggestion（Reviewer B Finding 3，65），依規則「只符合先前非 blocking triage note 的 finding 維持 `new`」，此處僅記一行交叉引用；因不是 `unresolved-prior` 也不是 `fix-introduced`，且 round 1 該 triage 的修正只是漏了 proposal 一處，故為非 blocking 並在本輪修正
- severity: Suggestion（自 Warning 55 降級）；confidence: 55；layer: design；location: design.md Decision 2 vs Decision 1、specs/ios-device-session「重連後 clear 失敗」第三條 AND；summary: reconnect 內的 clear 若 recovery 探到 `exited`，`markUSBDisconnected` 已清 session 並設 `interrupted`，而 clear 失敗分支無條件 stopTunnel 並覆寫為 `cleanupPending`，違反「MUST NOT 對已 exited 的 lease 呼叫 stopTunnel」；recommendation: 對 `usbDisconnected` 直接重拋；reviewer source: Reviewer V Finding 2；disposition: `fix-introduced`；introduced_by: r1 Fix Action「Critical 1（reconnect clear 失敗死局）」
- severity: Suggestion（自 Warning 75 降級）；confidence: 75；layer: design；location: tasks.md 2.1／2.2／2.3 的 `[P]`；summary: 2.2／2.3 依賴 2.1 的 seam 且共用檔案，不符 `[P]` 條件；recommendation: 移除 2.2／2.3 的 `[P]`；reviewer source: Reviewer V Finding 3；disposition: `fix-introduced`；introduced_by: r1 Fix Action「Suggestion（測試 seam）」
- severity: Suggestion；confidence: 50；layer: text；location: specs/location-simulation「terminal helper或tunnel failure」scenario；summary: 停止動作的 clear 遇 `exited` 時，該 scenario 的 THEN（interrupted）與「停止模擬與 clear 確認」（維持 stopping 並自動重備）不一致；recommendation: WHEN 限定為 `set`，並註明 clear 依停止 requirement；reviewer source: Reviewer V Finding 4；disposition: `new`

### 已過濾（confidence < 50，僅記錄）

- Reviewer V Finding 5（45）：master「工作區重置」的 busy 枚舉未含 `reconnecting`。

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 0
- non-blocking triaged finding count: 4
- critical_gap: false
- round_type: micro
- rationale: 兩個 blocking member 均由 Reviewer V 給出 resolved 判定並附證據，依 verified-resolution 自 cumulative set 移除；本輪新 finding 經 disposition 校正與信心過濾後皆非 blocking，pass condition 已成立。但本輪 fix actions 再度修改了 proposal、design、兩份 spec 與 tasks（含 fix-introduced 的分支修正與 `[P]` 調整），為確保修正不再引入新缺陷，主 agent 選擇進入下一輪 micro 驗證而非直接 passed。

## Fix Actions

- **disposition 校正**：Reviewer V Finding 1 的 `unresolved-prior` 校正為 `new`（原 tag `unresolved-prior`，校正後 `new`；證據：對應的 r1 finding 為 Reviewer B Finding 3，confidence 65，降為 Suggestion 後屬非 blocking triage note）。
- **proposal 殘留**：proposal.md Proposed Solution 第 4 點改為「與 `starting` 一致不持有 cleanup ownership、不顯示『停止模擬』按鈕」；Capabilities 條目加入「工作區重置」busy 枚舉。
- **fix-introduced（reconnect 內再次拔線）**：design.md Decision 2 改為先 capture 新 lease，clear 失敗為 `usbDisconnected` 時直接重拋、不拆除、不覆寫 state，其他 failure 才拆除；Implementation Contract 1／2 同步；specs/ios-device-session「重連後 clear 失敗」第三條 AND 加入 failure 分流與「MUST NOT 對已 exited 的 lease 呼叫 stopTunnel」；tasks.md 1.1 增列 exited 分支斷言、1.2 實作敘述同步。
- **fix-introduced（`[P]`）**：tasks.md 2.2 與 2.3 移除 `[P]`，僅保留 1.1 與 2.1。
- **scenario 措辭**：specs/location-simulation「terminal helper或tunnel failure」WHEN 限定為 `set`，並新增 AND 指明停止動作的 clear 依「停止模擬與 clear 確認」。
- **已過濾項目順帶處理**：specs/location-simulation 新增 MODIFIED「工作區重置」（正文與所有 scenario 逐字自 master 複製），busy 枚舉與「busy 狀態下 Reset disabled」scenario 加入 `reconnecting`；tasks.md 2.4 標題列入；proposal Capabilities 同步。
- 修正後重新執行 `validate`：通過。修正後機械自檢：註解配對 0／0、七個 MODIFIED 標題逐字存在於 master、「持有 cleanup ownership」無殘留、`[P]` 只剩 1.1 與 2.1。
- 修改檔案（5）：proposal.md、design.md、specs/ios-device-session/spec.md、specs/location-simulation/spec.md、tasks.md。change 目錄外無修改，不呼叫 touched record。

## Decision

next_round
