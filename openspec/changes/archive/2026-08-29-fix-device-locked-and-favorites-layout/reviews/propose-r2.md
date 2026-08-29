# Cash Propose Review — Round 2

## Reviewer Findings

`round_type` 為 micro，由單一 Reviewer V 對 cumulative blocking set 做 delta verification。

### Cumulative blocking set 逐條判定

| member | 來源 | 判定 | 依據 |
| --- | --- | --- | --- |
| 1 ADDED 與 MODIFIED requirement 矛盾 | R1 finding 1 | resolved | delta spec 主詞已改為失敗細節，`##### Example:` 明載該細節接著被分類為裝置螢幕鎖定；與 `classify` 行為一致 |
| 2 task 1.5 pure-refactor 理由不成立、分類順序零覆蓋 | R1 finding 2 | **unresolved** | 程式碼側已修（`classify` 與六個測試案例），但 `tasks.md` task 1.5 逐字未變，全文不含 `classify` |
| 3 stdout 被接到 stderr 例外之後 | R1 finding 3 | resolved | `detail` 改為 stderr 優先、stdout 後備，兩者不進同一次接合；兩個對應測試存在 |
| 4 MODIFIED requirement 過度宣稱七階段 | R1 finding 4 | resolved | 收斂為四個 CLI 階段並明文排除 tunnel 與 DVT；已核對 `run` 的呼叫端恰為該四個階段 |
| 5 design Risks 宣稱未寫入診斷紀錄 | R1 finding 5 | resolved | Risks 已據實改寫，與 `DeviceSetupStore` 的 metadata 寫入一致 |
| 6 漏判 `PasswordProtected` | R1 finding 6 | resolved | 程式碼、design Contract 1、delta spec 與測試四處同步 |

verified-resolution 移除紀錄：member 1、3、4、5、6 由 Reviewer V 於本輪確認解決並附行號證據，離開 cumulative blocking set。member 2 保留於 set 中。

### Critical

（無）

### Warning

1. `severity`: Warning／`confidence`: 100／`layer`: design／`disposition`: `unresolved-prior`（R1 blocking finding 2）
   - `location`: `tasks.md` task 1.5
   - `summary`: R1 finding 2 的 `tasks.md` 修復完全未落地，task 1.5 與 Round 1 逐字相同，仍以 `pure-refactor：行為斷言由既有測試涵蓋` 作為免除紅燈的理由；`delivery` 不含承載新斷言的測試檔，`success` 仍指既有測試。R1 的 `## Fix Actions` 對此的宣稱與檔案內容不符。
   - `recommendation`: 依實際實作改寫 task 1.5 的敘述、`delivery`、`success` 與 `red`。

### Suggestion

2. `confidence`: 100／`layer`: design／`disposition`: `new`：`tasks.md` task 1.1 與 1.2 的 `success` 仍寫「四個摘要案例」，與 Contract 8 的案例清單及實際測試數不符；task 1.1 也仍留「原樣保留」措辭，與已改為「取最後一個有意義的錯誤行」的 proposal 與 spec 不一致。（與 finding 1 同因：同一批 `tasks.md` 編輯整批未寫入。）
3. `confidence`: 50／`layer`: design／`disposition`: `fix-introduced`／`introduced_by`: R1 finding 3 的修復「`summarize` 改為兩個串流各自獨立摘要」
   - `summary`: per-stream 改動使 `classify` 只在單一被選中的串流摘要上做關鍵字判定。舊行為串接後判定，關鍵字出現在任一串流都能命中；新行為下 standard error 只要有任何非雜訊行，standard output 就整段被丟棄，其中的鎖定或授權標記不會進入分類。delta spec 只要求兩串流不得接合為同一句，並未要求分類只看單一串流。
4. `confidence`: 50／`layer`: design／`disposition`: `unresolved-prior`（R1 finding 2 的 Reviewer B 分支）：授權分類路徑缺少方框式 traceback 的端到端 oracle，兩個授權測試的輸入都是單行純文字，走 `lastMeaningfulLine` 分支而非 `exceptionSummary` 分支。
5. `confidence`: 75／`layer`: design／`disposition`: `new`：`makeIsolatedDefaults` 以 UUID 命名建立 suite 且結束時不清理，理論上每次執行會累積不重複的 suite。
6. `confidence`: 100／`layer`: design／`disposition`: `new`：Contract 1 稱 `summarize` 回傳截斷後細節「供顯示」，但 production 端只呼叫 `classify`，`summarize` 在 `iPhoneLocationMove/` 下零呼叫，實際顯示用截斷發生在 `classify` 內部。

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 1
- 非 blocking triaged finding count: 5
- `critical_gap`: false
- `round_type`: micro

rationale：Reviewer V 對六個 member 全數給出判定，五個確認解決並移出 cumulative blocking set，member 2 判定 unresolved 且附逐字比對證據，維持 blocking。finding 3 的 `disposition` 為 `fix-introduced`，但 confidence 50 經 filter 降級為 Suggestion，依規則非 blocking；finding 4 為 Suggestion 亦非 blocking。set 中仍有一筆 blocking Warning，因此不得判為 `passed`。

## Fix Actions

**Round 1 Fix Actions 記載不實之更正**：R1 `## Fix Actions` 宣稱已「改寫 `tasks.md` task 1.5 的敘述、`delivery`、`red` 與 `success`」，並宣稱同步了 task 1.1 的 `success` 與「原樣保留」措辭。實際上該批 `tasks.md` 編輯完全未寫入檔案：執行編輯的指令碼在迴圈中對第四筆替換做斷言失敗而中止，而寫檔動作位於迴圈之後，導致前三筆已成功的替換一併被丟棄。R1 的 round file 於 loop 進行中不可變更，故於本輪記錄此更正。本輪改為逐筆讀寫，每筆替換各自寫檔，並於套用後以 grep 驗證結果。

- finding 1（member 2）：改寫 `tasks.md` task 1.5，敘述改為「把輸出加階段轉為 typed 失敗抽為 `classify` pure function」，明載分類順序原本住在 private actor 內而既有測試全走 `FakePymobiledeviceBoundary` 因此不存在可涵蓋的既有測試；`delivery` 補上 `iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift`；`success` 改為指名六個 classify 案例；`red` 移除 pure-refactor 理由。已 grep 驗證 `pure-refactor` 於 task 1.5 為 0 次、`classify` 出現 1 次。
- finding 2：`tasks.md` task 1.1 與 1.2 的 `success` 改為與 Contract 8 一致的案例描述並補上 standard output 隔離與長度上限截斷；task 1.1 的「原樣保留」改為「取最後一個有意義的錯誤行」。已 grep 驗證兩個舊措辭殘留皆為 0。
- finding 3：`classify` 改為對 standard error 與 standard output 兩個串流各自的摘要分別做鎖定與授權判定，顯示用細節仍只取單一串流以維持 R1 finding 3 的修復；新增 `testLockMarkerPrintedOnlyToStandardOutputIsStillClassified` 作為 oracle；delta spec 與 design Contract 1、Contract 8 同步記載此區分。
- finding 4：新增 `testPairingTracebackStillClassifiesAsAuthorization`，以 pairing 失敗的方框式 traceback 為輸入斷言回傳授權被拒絕，使授權路徑與鎖定路徑的 oracle 對等。
- finding 5：triage note。已實測驗證：完整測試套件執行後 `~/Library/Preferences/` 下 `iPhoneLocationMoveTests-*` 殘留檔數為 0，因為使用該預設值的測試都不寫入最愛，suite 從未被具體化。實際 user-state 汙染為零，僅存在「未來若有測試寫入則命名無上限」的設計面風險。不改動該 helper：改為固定命名會讓同一測試內先後建立的 hosting view 共用 domain，引入測試間狀態耦合，代價高於目前為零的汙染。
- finding 6：Contract 1 改為說明 `summarize` 是對外暴露的測試接縫，與 `classify` 共用細節產生與截斷邏輯，production 端的顯示用截斷由 `classify` 內部產生。

fix 後重跑：`validate` 通過；完整 macOS 測試套件 238 個測試全綠；Python protocol 測試 14 個通過。

post-fix mechanical self-check：annotation lint、title identity、identifier cross-grep 全部通過。

無 `未修復：裁判面保護` 記錄。

## Decision

next_round
