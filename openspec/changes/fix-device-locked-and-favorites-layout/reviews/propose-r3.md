# Cash Propose Review — Round 3

## Reviewer Findings

`round_type` 為 micro，由單一 Reviewer V 對 cumulative blocking set 做 delta verification。

### Cumulative blocking set 逐條判定

| member | 來源 | 判定 | 依據 |
| --- | --- | --- | --- |
| 2 task 1.5 pure-refactor 理由不成立、分類順序零覆蓋 | R1 finding 2 | resolved | `tasks.md:7` 逐字比對確認重寫已落地：`pure-refactor` 於 task 1.5 為 0 次、`delivery` 已含測試檔、`success` 指名的六個 classify 案例在測試檔中全部實際存在 |

verified-resolution 移除紀錄：member 2 由 Reviewer V 於本輪確認解決並附逐字證據，離開 cumulative blocking set。Reviewer V 同時確認 Round 2 六條 Fix Action 全數落地，無「宣稱已修但未落地」情形，Round 2 改採逐筆讀寫的做法有效。

### Critical

（無）

### Warning

1. `severity`: Warning／`confidence`: 100／`layer`: design／`disposition`: `fix-introduced`／`introduced_by`: Round 2 `## Fix Actions` 的 finding 1（改寫 task 1.5 的 `red`）
   - `location`: `tasks.md` task 1.5 的 `red`；`iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift`
   - `summary`: 新寫的 `red` 宣稱「分類順序錯誤時鎖定輸入被判為 authorizationDenied」，但既有六個 classify 案例的鎖定輸入沒有任何一個同時命中授權關鍵字，把鎖定與授權兩個分支對調測試套件仍會全綠。該順序在 artifact 上被宣稱有 oracle，實際零覆蓋；`design.md` 的決策段又自承兩組關鍵字不重疊，兩份 artifact 說法互相牴觸。
   - `recommendation`: 新增可證偽該順序的案例並補入 `success`，或把 `red` 改為只宣稱可觀察的條件並在 design 註明關鍵字互斥。

2. `severity`: Warning／`confidence`: 100／`layer`: design／`disposition`: `fix-introduced`／`introduced_by`: Round 2 `## Fix Actions` 的 finding 3（`classify` 改為兩串流分別判定並同步 delta spec）
   - `location`: `specs/ios-device-session/spec.md` 分類段落；`PymobiledeviceAdapter.swift` 的 `classify` 與 `streamSummary`
   - `summary`: delta spec 寫「分類 MUST 同時檢視 standard error 與 standard output 兩個串流」，但實作檢視的不是串流，而是 `streamSummary` 收斂後的單一行；沒有方框邊界時只有最後一個非雜訊行會進入分類，其餘各行一律被丟棄。屬與 R1 finding 4 同型的過度宣稱缺陷。
   - `recommendation`: 把該句收斂為「對各自產生的摘要分別判定」，或改為掃描串流全文使 MUST 名副其實。

### Suggestion

3. `confidence`: 50／`layer`: design／`disposition`: `fix-introduced`／`introduced_by`: Round 2 finding 3：把 stdout 納入分類是單向放寬，`markers` 中任一元素命中即改變結果。當 stderr 帶真正失敗原因、而 stdout 摘要行碰巧含授權關鍵字時，使用者會拿到錯誤指引且 stderr 摘要被整段丟棄。此與 R1 finding 3 所確立的「stdout 可信度低於 stderr」原則方向相反：顯示層視 stdout 為後備，分類層卻視其為等權證據。
4. `confidence`: 50／`layer`: design／`disposition`: `new`：`deviceLocked` 與 `authorizationDenied` 都不帶 associated message，分類命中時寫入診斷紀錄的只剩分類名稱，原始摘要完全不落地；`design.md` Risks 只描述「減少寫入量」，未涵蓋此「寫入量為零」的分支。
5. `confidence`: 50／`layer`: design／`disposition`: `fix-introduced`／`introduced_by`: Round 2 finding 3：`proposal.md` 是本次 fix propagation 唯一漏掉的 artifact，仍只寫 stdout 作為顯示後備，未提及分類同時檢視兩個串流。

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 2
- 非 blocking triaged finding count: 3
- `critical_gap`: false
- `round_type`: micro

rationale：member 2 經逐字驗證確認解決並移出 set，Round 2 的六條 Fix Action 亦全數確認落地。但本輪新增兩筆 confidence 100 且 `disposition` 為 `fix-introduced` 的 Warning，依規則進入 cumulative blocking set 並為 blocking：finding 1 指出 Round 2 新寫的 `red` 宣稱了一個實際不存在的 oracle，finding 2 指出 Round 2 同步進 spec 的措辭是過度宣稱。findings 3 與 5 同為 `fix-introduced` 但 confidence 50，經 filter 降級為 Suggestion，非 blocking。set 中仍有 blocking Warning，因此不得判為 `passed`。

## Fix Actions

- finding 1：新增 `testDeviceLockTakesPrecedenceOverAuthorizationOnTheSameLine`，以同時含授權與鎖定標記的構造輸入斷言回傳 `deviceLocked`。已以暫時對調 `classify` 內兩個分支的實驗確認該測試會失敗並回報 `authorizationDenied`，證明其為有效 oracle。查閱 pymobiledevice3 的 `lockdown.py` 確認真實鎖定訊息為「your device is protected with password, please enter password in device and try again」，不含任何授權關鍵字，故順序僅能以刻意構造的輸入觀察；此事實已寫入測試註解與 task 1.5 的 `red`，該 `red` 也改為只宣稱可觀察的條件（分支對調時該案例回傳 authorizationDenied）。
- finding 2：delta spec 的分類段落改為「MUST 對 standard error 與 standard output 各自產生的摘要分別判定」，並明載「分類標記若落在該串流被雜訊過濾或未被選為摘要的行上，則不在分類的觀察範圍內」；對應 scenario 的 GIVEN 補上「標記出現在 standard output 的摘要行上」。未改採掃描串流全文，因為 traceback 的原始碼回顯行可能含 `Pairing` 等字樣，全文掃描會引入假陽性，代價高於目前的收斂範圍。`design.md` Contract 1 同步補上「分類的觀察範圍是各串流收斂後的摘要行，不是串流全文」。
- finding 3：`classify` 改為依串流優先序逐一判定——先對 standard error 的摘要判定鎖定與授權，命中即回傳；未命中才輪到 standard output 的摘要。此使分類層的串流優先序與顯示層一致，同時保留「標記只出現在 standard output」的涵蓋。新增 `testStandardErrorClassificationWinsOverStandardOutput` 作為 oracle。spec 與 design Contract 1 同步記載此優先序。
- finding 4：`design.md` `## Risks / Trade-offs` 補記兩個分類都不攜帶 associated message，分類命中時原始摘要完全不落地至診斷紀錄，並說明本次接受此取捨、不另存未分類摘要。
- finding 5：`proposal.md` `## Proposed Solution` 補上顯示來源與分類輸入的區分。

post-fix mechanical self-check 抓到並修復：count-consistency——task 1.5 的 `success` 原寫「八個案例」，實際 classify 測試方法有十個（漏列 lockdown 原始鎖定錯誤字串與單行 pairing 兩個既有案例）。已改為十個並逐一具名。annotation lint、title identity、identifier cross-grep 通過。

fix 後重跑：`validate` 通過；完整 macOS 測試套件 240 個測試全綠。

無 `未修復：裁判面保護` 記錄。

## Decision

next_round
