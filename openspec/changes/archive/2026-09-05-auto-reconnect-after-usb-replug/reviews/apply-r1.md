# Cash Apply Review — Round 1

## Reviewer Findings

（以下為信心度過濾後的結果。過濾前 Reviewer A 提出 3 Warning／2 Suggestion，Reviewer B 提出 0 Critical／0 Warning／5 Suggestion；依 `location + summary` 聚合後，A1≡B2、A3≡B5 各合併為一筆。）

### Critical

無。

### Warning

無。過濾前的三個 Warning 皆因 `confidence ∈ [50, 80)` 降級為 `Suggestion`，另有一個經主 agent 驗證為誤報而降至 25 並丟棄，詳見 `## Fix Actions` 的降級軌跡。

### Suggestion

1. `severity`: Suggestion / `confidence`: 60 / `layer`: design / `disposition`: new
   - `location`: `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift:207` 與 `:220-235`（`reconnect()` 的 clear 失敗分支）
   - `summary`: `candidateLease` 在 `sendClear` 之前 capture，與 design Decision 2 明文的「在第一個 `await` 前同步 capture」時點不同；若 `sendClear` 內的 recovery 成功換掉 `tunnelLease`，被拆除的會是舊 lease。
   - `recommendation`: 把 `let candidateLease = tunnelLease` 移進 `catch` 分支、放在 `session = nil` 等清空之前的第一行。
   - reviewer source: Reviewer A（Warning/60）＋ Reviewer B（Suggestion/40），合併取較高信心度。
   - `introduced_by`: `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift:207`，本次新增的 `let candidateLease = tunnelLease` 一行。
   - 主 agent 驗證：目前不可達。`recoverTransport` 成功時 `sendClear` 後續三個 guard（`self.session?.generation == context.generation`、`generation == context.generation`、`reply.requestID == context.requestID`）必然通過，因此「recovery 成功且 clear 仍失敗」不存在；`recoverTransport` 失敗時它自己已拆除 candidate 且不改寫 `tunnelLease`，預先 capture 與事後 capture 等價。屬措辭偏離與脆弱點，非行為缺陷。

2. `severity`: Suggestion / `confidence`: 70 / `layer`: design / `disposition`: new
   - `location`: `iPhoneLocationMoveTests/SimulationStoreTests.swift` 的 `testQuitWaitsForAPendingReconnectBeforeClearing`；`tasks.md` 2.2 的 `success:` 與 `design.md` Decision 3／Contract 6 的「等待期間再 enqueue 一個 `confirmPoint` 亦會被等到」
   - `summary`: 該測試的第二個 `confirmPoint` 在 `userActionTask != nil` 時被入口 guard 擋成 no-op，從未成為第二個 in-flight 動作，因此對「亦會被等到」這句宣稱沒有鑑別力；把 `stopForQuit()` 的 `while` 改成 `if` 該測試仍會通過。屬 signal `artifact-claimed-coverage-exceeds-oracle`。
   - `recommendation`: 斷言 `queued` 期間 `recordedSetCallCount()` 未增加以明示「第二個動作被忽略」的實際 contract，並把 design 該句改為與 spec `#### Scenario: reconnect 進行中的其他要求與退出`（「MUST NOT 觸發第二次 reconnect，也 MUST NOT 改變進行中動作的 state」）一致的措辭。
   - reviewer source: Reviewer A（Warning/70）＋ Reviewer B（Suggestion/55），合併取較高信心度。

3. `severity`: Suggestion / `confidence`: 65 / `layer`: design / `disposition`: new
   - `location`: `design.md` `## Risks / Trade-offs` 最後一項
   - `summary`: 「`teardownForQuit` 的既有 catch 會把 `interrupted` 覆寫為 `cleanupPending`」這個程式碼宣稱不成立——`markUSBDisconnected` 已把 `session` 與 `tunnelLease` 設為 nil，`teardownForQuit` 的 `if let session, let lease = tunnelLease` 整段被略過，state 直接進 `.disconnected`。
   - `recommendation`: 改寫為實際機制（USB 未插回時 stop 的 reconnect 失敗使 `cleanupFailure` 非 nil，退出停在 `AppQuitState.cleanupFailed`），或刪除該條。
   - reviewer source: Reviewer A。主 agent 已於 `PymobiledeviceAdapter.swift:458` 逐行驗證該宣稱確實不成立。

4. `severity`: Suggestion / `confidence`: 60 / `layer`: design / `disposition`: new
   - `location`: `iPhoneLocationMoveTests/SimulationStoreTests.swift` 的 `waitForPendingReconnect()`、`iPhoneLocationMoveTests/ContentViewTests.swift` 的 `waitForPendingReconnect()`
   - `summary`: `while pendingReconnect == nil { await Task.yield() }` 無迭代上限；若日後回歸讓 store 不再呼叫 `reconnect()`，本次新增的六個案例會無限自旋到 `xcodebuild` 整體 timeout，而非給出可讀的失敗訊息。
   - `recommendation`: 加上迭代上限後 return，比照既有 `waitForPendingTunnelStart()` 的有界等待風格。
   - reviewer source: Reviewer B。`introduced_by`: 本次新增的兩個 `waitForPendingReconnect()` 測試 seam。

5. `severity`: Suggestion / `confidence`: 50 / `layer`: design / `disposition`: new
   - `location`: `iPhoneLocationMove/Features/Simulation/SimulationStore.swift` 的 `failureCaseName(_:)`
   - `summary`: 以 `String(describing:)` 取左括號前綴做 redaction，依賴「`DeviceLocationError` 沒有 `CustomStringConvertible`」這個隱含前提；日後有人加上 `description` 會使 redaction 無聲退化。屬 signal `diagnostic-sensitive-detail-no-redaction`。
   - `recommendation`: 改為對 `DeviceLocationError` 明確 `switch` 回傳固定字面值，使新增 case 時編譯器強制更新。
   - reviewer source: Reviewer B。`introduced_by`: 本次新增的 `failureCaseName(_:)`。

6. `severity`: Suggestion / `confidence`: 50 / `layer`: design / `disposition`: new
   - `location`: `iPhoneLocationMove/Features/Simulation/SimulationStore.swift` 的 `performInitialSet` current 判準 guard
   - `summary`: reconnect 已成功但 current 判準不成立時丟 `staleGeneration`，未寫回 `generation`，理論上會停在舊 generation 的死局。
   - `recommendation`: 改丟 `usbDisconnected`，或丟出前先寫回 `generation`。
   - reviewer source: Reviewer B。Reviewer B 自述目前不可達（`.reconnecting` 期間 `activeSessionID == nil`，其餘入口皆以 `activeSessionID`／`routeSession` 為 guard，single-flight 亦擋掉第二個使用者動作），且 `design.md` Decision 3 明文自述「此檢查是防禦」。

7. `severity`: Suggestion / `confidence`: 50 / `layer`: design / `disposition`: new
   - `location`: `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift` 的 exited 分支忽略 `markUSBDisconnected` 回傳值
   - `summary`: `markUSBDisconnected` 在 generation 無法遞增時回傳 `false` 且不清除 session，此時仍拋 `usbDisconnected`，之後的 mutation 會走 `staleGeneration`。
   - `recommendation`: exited 分支依回傳值分流，或在 design Decision 1 明文記載此 exhausted-generation 分支。
   - reviewer source: Reviewer A。主 agent 判定：`DeviceSessionGeneration` 為 UInt64 遞增，耗盡在實務上不可達；為其撰寫分流屬 contract 未要求的防禦性錯誤處理。

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 0
- 非阻塞 triaged finding 數: 7
- `critical_gap`: false
- `round_type`: full

rationale：本輪是 unseeded run 的第一輪，因此過濾後所有存活的 Critical 與 Warning 都會是阻塞項。兩位 reviewer 共提出 10 筆 finding，聚合後為 8 筆；其中一筆（exited 分支缺 ownership gate）經主 agent 逐行驗證為誤報而降至 25 丟棄，一筆（candidateLease capture，Reviewer B 版本）原始信心度 40 低於門檻而丟棄，其餘全部落在 `confidence ∈ [50, 80)` 而降級為 `Suggestion`。沒有任何 finding 達到 `confidence ≥ 80`，也沒有任何 finding 提出足以觸發 Safety exception 的具體資料遺失或安全性證據——Reviewer B 明確判定 `reconnect-partial-failure-identity-drift`、`actor-reentrant-recovery-generation-gate`、`candidate-transport-identity-lifecycle-order`、`mutation-terminal-state-type-split` 四個相關 signal 皆未被違反，且本次 diff 沒有引入複雜度 finding。因此 post-filter cumulative blocking set 為空，pass 條件成立。

## Fix Actions

None; pass condition met.

降級軌跡（disposition correction）：Reviewer A 的「exited 分支在 `markUSBDisconnected` 之前未重驗 captured ownership」原為 Warning/60。主 agent 於 `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift` 逐行確認 `try validateRecoveryOwnership(ownership)` 就位於 `let status = try await boundary.tunnelStatus(oldLease)` 之後、`guard status.state == .running` 之前，兩者之間沒有任何 suspension point，Reviewer B 亦獨立得出「每個外部 side effect 前後都有 `validateRecoveryOwnership(ownership)`，未違反」的結論。判定為誤報，依「Common false positives」規則降至 `confidence` 25 並丟棄。

降級軌跡（低於門檻）：Reviewer B 的「`candidateLease` 在 `sendClear` 之前 capture」原始 `confidence` 40，低於 50 而丟棄；同一 issue class 的 Reviewer A 版本（60）已合併保留為 Suggestion 1。

triage 註記：上列 7 筆 Suggestion 皆為非阻塞的 `new` finding，記錄於本輪 `## Fix Actions` 並在完成輸出中列出。其中無 Critical，故不建議另開 follow-up change proposal。

pre-round mechanical self-check（本輪 reviewer 派出前執行，非 reviewer finding，不影響決策）：spec delta 的 `<!--`／`-->` 計數皆為 0 且無游離 `---`；跨 artifact 數量宣稱與實際相符（六個 fake、location-simulation 1 ADDED + 5 MODIFIED、DisconnectReconnectIntegrationTests 既有 3 + 新增 2 = 5）；`design.md` 定義的 20 個識別字與 12 個檔案路徑全部存在且拼寫一致；7 個 MODIFIED requirement 標題與對應 master spec 逐字相符；7 個 MODIFIED requirement 皆完整承接 master 的所有 scenario。`openspec/signals/` 中沒有任何 `open` signal 帶 `check` 欄位，故改以 best-effort 判斷處理，未產生 `範圍外 check 失敗` 或 fallback 註記。

## Decision

passed
