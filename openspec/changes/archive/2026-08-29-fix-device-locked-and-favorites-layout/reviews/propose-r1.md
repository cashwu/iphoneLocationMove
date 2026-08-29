# Cash Propose Review — Round 1

## Reviewer Findings

Round 1 為 unseeded run 的第一輪，因此所有通過 confidence filter 的 Critical 與 Warning 皆為 blocking，且不需標註 `disposition`。

### Critical

（無）

### Warning

1. `severity`: Warning／`confidence`: 100／`layer`: design／來源：Reviewer A
   - `location`: `specs/ios-device-session/spec.md` ADDED requirement 與其 `##### Example:`，對上同檔 MODIFIED requirement
   - `summary`: 同一份 delta 的兩條 requirement 對「鎖定裝置輸出」給出互相矛盾的使用者可見結果——ADDED 的 Example 宣稱使用者會看到例外摘要，但 MODIFIED 與實作都把該輸入分類為 `deviceLocked`，使用者實際看到的是固定的解鎖指引。
   - `recommendation`: 把 ADDED requirement 的主詞從「使用者可見訊息」改為「失敗細節」，並在 Example 明載該細節接著被分類為裝置螢幕鎖定。

2. `severity`: Warning／`confidence`: 100／`layer`: design／來源：Reviewer A 與 Reviewer B 獨立提出，依 `location + summary` 合併
   - `location`: `tasks.md` task 1.5；`iPhoneLocationMove/Device/PymobiledeviceAdapter.swift` 的 `LivePymobiledeviceBoundary.run`
   - `summary`: task 1.5 宣稱 `pure-refactor` 且「行為斷言由既有測試涵蓋」，但 `LivePymobiledeviceBoundary` 是 `private actor`，測試無法建構；既有 `PymobiledeviceAdapterTests` 全走 `FakePymobiledeviceBoundary` 直接注入 typed error，不經過被改動的 `run()`。新的「先鎖定、再授權、最後 prerequisite」分類順序因此零自動化覆蓋。Reviewer B 另指出授權判定的輸入從整段 stderr 加 stdout 變成收斂後的單行摘要，屬行為變更而非重構。
   - `recommendation`: 把分類抽為可直接測試的 pure function，並誠實改寫 task 1.5 的 `red` 與 `success`。

3. `severity`: Warning／`confidence`: 100（Reviewer B 原評 75，主 agent 依實驗直接證據修正）／`layer`: design／來源：Reviewer B
   - `location`: `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift` 的 `summarize`
   - `summary`: `summarize` 把 standard error 與 standard output 串成同一份行陣列後才尋找方框邊界，因此只要 stdout 非空，其內容就會被接到例外摘要後面，形成由兩個獨立輸出串流拼成的假句子。
   - `recommendation`: 兩個串流各自獨立摘要，stdout 只在 stderr 無可用內容時作為來源。

4. `severity`: Warning／`confidence`: 100（Reviewer B 原評 75，主 agent 依程式碼路徑直接證據修正）／`layer`: design／來源：Reviewer B
   - `location`: `specs/ios-device-session/spec.md` MODIFIED requirement「裝置 prerequisite 準備順序」
   - `summary`: requirement 明列七個階段並宣告「鎖定可能發生在任一階段但修復動作相同」，但鎖定分類只掛在走 `run()` 子行程的階段；tunnel 走 XPC helper、DVT 走 helper 程序，兩者都不做鎖定判定，requirement 因此過度宣稱。
   - `recommendation`: 把涵蓋範圍收斂為透過 `pymobiledevice3` CLI 執行的階段，並在 proposal `## Non-Goals` 明記 tunnel 與 DVT 路徑不在本次範圍。

5. `severity`: Warning／`confidence`: 100（Reviewer B 原評 75，主 agent 依程式碼直接證據修正）／`layer`: design／來源：Reviewer B
   - `location`: `design.md` `## Risks / Trade-offs` 敏感值段落
   - `summary`: design 以「本次僅在使用者可見的失敗訊息呈現，未寫入持久診斷紀錄」作為不做遮蔽的理由，但該前提為假：`DeviceSetupStore` 的失敗路徑會把 typed 失敗寫入 diagnostic metadata，經 `DiagnosticLogger` 落地至使用者的 `diagnostic.jsonl`。結論碰巧仍成立（本次是減少寫入量），但理由會誤導後續判斷。
   - `recommendation`: 據實改寫該風險段落，寫明摘要確實會經 `prerequisiteFailed` 的 message 進入診斷紀錄，且本次相對既有行為是減少寫入量而非未寫入。

6. `severity`: Warning／`confidence`: 100（Reviewer B 原評 25，主 agent 依 pymobiledevice3 原始碼直接證據修正）／`layer`: design／來源：Reviewer B
   - `location`: `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift` 的 `isDeviceLockedFailure`
   - `summary`: 鎖定關鍵字只涵蓋 `devicelocked`、`device is locked` 與 `passwordrequired`。lockdown 回傳的原始錯誤字串是 `PasswordProtected`，僅在包裝成 `PasswordRequiredError` 後才出現 `PasswordRequired`；摘要落在只印出原始錯誤字串的路徑時會漏判。
   - `recommendation`: 補上 `passwordprotected` 關鍵字，並在 spec 明訂鎖定判定須涵蓋原始錯誤字串與包裝後例外名稱兩種形式。

### Suggestion

以下為 confidence 落在 50 至 79 而由 filter 降級的非 blocking findings，全部已在本輪一併修復：

7. `confidence`: 75／`layer`: design／Reviewer A：長度上限是一條 SHALL，但 delta 無對應 scenario、Contract 8 測試清單與 task 1.1 的 `success` 都不含截斷案例。
8. `confidence`: 75／`layer`: design／Reviewer A：`specs/favorite-places/spec.md` 的「未超過上限時 MUST NOT 預留額外空白」與「清單內可捲動存取所有收藏」兩條行為無任何 task 覆蓋。
9. `confidence`: 75／`layer`: design／Reviewer A：proposal 與 spec 寫「原樣保留」，design 與實作是「取最後一個有意義的行」，措辭與行為不符且該收斂未記入取捨。
10. `confidence`: 75／`layer`: text／Reviewer A：`iPhoneLocationMoveTests/DeviceFailurePresentationTests.swift` 列於 proposal `## Impact` 且有 Contract 規範，卻未出現在任何 task 的 `delivery`。
11. `confidence`: 75／`layer`: design／Reviewer A：Contract 1 稱「三者的字串比對皆不分大小寫」，但 `summarize` 內部的雜訊判定是大小寫敏感。
12. `confidence`: 50／`layer`: text／Reviewer A：Contract 3 稱「兩個既有的 switch」，實際有三個帶 `default` 的 switch 吸收新 case。
13. `confidence`: 60／`layer`: design／Reviewer B：400 字元截斷發生在分類之前，長摘要可能讓鎖定標記被切掉而退回 `prerequisiteFailed`。
14. `confidence`: 50／`layer`: design／Reviewer B：design 稱 rich 只在空白處折行，但 rich 對超長無空白 token 會硬折，接合時會插入不存在的空白使識別碼失真；此限制未列入 Risks。
15. `confidence`: 50／`layer`: design／Reviewer B：新建的隔離 UserDefaults suite 只在建立時清除，測試結束後未清理，於執行機器留下 user-state。
16. `confidence`: 50／`layer`: design／Reviewer B：`isNoise` 內同時存在 regex 與手寫 `Substring` 掃描兩套機制，手寫掃描未帶來 regex 做不到的能力（複雜度 lens）。

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 6
- 非 blocking triaged finding count: 10
- `critical_gap`: false
- `round_type`: full

rationale：兩位 reviewer 獨立回報後依 `location + summary` 合併，Reviewer A 的 task 1.5 finding 與 Reviewer B 的 finding 3 判定為同一 defect，合併後取 `layer == design`。主 agent 對四筆 Reviewer B findings 依直接證據上修 confidence 至 100：finding 3 以還原舊寫法的實驗重現拼接假句、finding 4 以 tunnel 與 DVT 不經 `run()` 的程式碼路徑佐證、finding 5 以 `DeviceSetupStore` 至 `DiagnosticLogger` 的寫入鏈佐證、finding 6 以 pymobiledevice3 的 `lockdown.py` 原始碼佐證。無 Critical，因此 `critical_gap` 為 false；但 cumulative blocking set 仍有 6 筆 blocking Warning 未經後續 reviewer 確認解決，依 pass 條件不得判為 `passed`。

## Fix Actions

pre-round mechanical self-check（spawn reviewers 前，inline 執行）抓到並修復：

- count-consistency：`proposal.md` 原稱「每多一筆最愛固定增加 22 點，因此第一筆收藏就會把主要動作推出可視範圍」，但 597.5 加 22 為 619.5 仍在 620 之內，因果推論不成立；實測第一筆為加 54（區塊標題、區塊間距與一列一併出現），其後每筆加 22。同時「二十筆增加 440 點」係以錯誤的 22 推算且 20 筆在舊版面下未實測。已改為只引用實測值並區分首筆與後續增量。`design.md` 對應敘述同步修正，並把未實測的二十筆推算值改為實測的八筆 805.5。
- annotation lint、title identity、identifier cross-grep 均無問題。

reviewer findings 修復（依 finding 編號）：

- finding 1：重寫 `specs/ios-device-session/spec.md` 的 ADDED requirement，標題改為「裝置準備失敗細節只保留可行動摘要」，主詞由使用者可見訊息改為失敗細節，並在 `##### Example:` 明載該細節接著被分類為裝置螢幕鎖定、使用者看到的是解鎖指引。
- finding 2：於 `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift` 新增 `PymobiledeviceFailureSummary.classify` pure function 承載分類順序，`run` 改為直接丟出其結果；於 `iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift` 新增五個 classify 案例（DDI 階段鎖定、trust 階段鎖定、pairing 授權、未分類保留階段與摘要、標記落在上限之後仍分類）；改寫 `tasks.md` task 1.5 的敘述、`delivery`、`red` 與 `success`，移除不成立的 pure-refactor 理由。
- finding 3：`summarize` 改為兩個串流各自獨立摘要，stdout 只在 stderr 無可用內容時作為來源；新增 `testStandardOutputIsNotSplicedOntoTheStandardErrorException` 與 `testStandardOutputIsUsedOnlyWhenStandardErrorHasNothingUsable`。已以暫時還原舊串接寫法的實驗確認新測試會失敗並輸出拼接假句，確保其為有效 oracle。
- finding 4：MODIFIED requirement 的鎖定分類涵蓋範圍收斂為透過 `pymobiledevice3` CLI 執行的四個階段，並明文排除 tunnel 與 DVT helper readiness；`proposal.md` `## Non-Goals` 新增對應條目。
- finding 5：改寫 `design.md` `## Risks / Trade-offs` 的敏感值段落，據實寫明摘要會經 `prerequisiteFailed` 的 message 進入 `diagnostic.jsonl`，本次相對既有行為是減少寫入量而非未寫入。
- finding 6：`isDeviceLockedFailure` 補上 `passwordprotected` 關鍵字；新增 `testRawLockdownPasswordProtectedIsClassifiedAsDeviceLocked`；MODIFIED requirement 新增「原始鎖定錯誤字串同樣被辨識」scenario；`tasks.md` task 3.2 擴充為涵蓋 DDI 與 trust 兩個階段並要求記錄實際觀察到的鎖定錯誤字串。
- finding 7：ADDED requirement 新增「超過長度上限的細節被截斷」與「分類標記位於長度上限之後仍能分類」兩個 scenario；Contract 8 與 task 1.1 的 `success` 同步補齊；新增 `testSummaryLongerThanTheDisplayLimitIsTruncated` 與 `testLockMarkerBeyondTheDisplayLimitStillClassifies`。
- finding 8：`testFavoritesListNeverPushesDeviceControlsOutOfTheSidebar` 補上渲染列數等於收藏數、以及門檻下高度小於門檻上高度兩個斷言；Contract 10 與 task 2.3 同步。
- finding 9：`proposal.md` 與 spec 的措辭改為「取最後一個有意義的錯誤行」，與 design 及實作一致。
- finding 10：`iPhoneLocationMoveTests/DeviceFailurePresentationTests.swift` 加入 task 1.4 的 `delivery`。
- finding 11：Contract 1 改為「兩個判定函式的字串比對不分大小寫；摘要的雜訊判定依 pymobiledevice3 固定的輸出樣式做大小寫敏感比對」。
- finding 12：Contract 3 移除錯誤數字，改為「既有帶 `default` 分支的 switch 會吸收新 case」。
- finding 13：`classify` 在未截斷的細節上進行分類，截斷只套用於顯示用細節；新增 `testLockMarkerBeyondTheDisplayLimitStillClassifies` 作為 oracle。
- finding 14：`design.md` `## Risks / Trade-offs` 新增 rich 硬折限制條目，並說明此限制影響可讀性而非分類正確性。
- finding 15：版面測試的隔離 suite 於 `defer` 清除持久化內容並移除 suite 註冊；Contract 10 同步記載。已驗證清理後殘留檔內容為空。macOS 的 `cfprefsd` 仍會保留三個空殼 plist 檔，此為平台行為，測試層無法消除。
- finding 16：`isSourceEcho` 手寫掃描併入 `isNoise` 的 regex pattern 陣列，移除只為其存在的 `framePointer` 與 `sourceGutter` 兩個常數。

fix 後重跑：`validate` 通過；完整 macOS 測試套件 236 個測試連續兩次全綠；Python protocol 測試 14 個通過。

triage note（非本輪 reviewer finding，記錄供後續參考）：`iPhoneLocationMoveTests/SimulationStoreTests.swift` 的 `testTimeoutHelperAndTunnelFailuresStopProducerWithTypedInterruption` 在一次完整套件執行中出現 `Condition did not become true` 的間歇失敗，單獨執行連續三次通過、完整套件連續兩次通過。該測試與本次改動無交集，屬既有的 timing flake，不列入本 change 的 blocking set。

post-fix mechanical self-check：annotation lint、title identity、identifier cross-grep 與殘留識別字掃描全部通過。

無 `未修復：裁判面保護` 記錄。

## Decision

next_round
