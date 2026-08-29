# Cash Propose Review — Round 5

## Reviewer Findings

`round_type` 為 micro，由單一 Reviewer V 對 cumulative blocking set 做 delta verification。

### Cumulative blocking set 逐條判定

| member | 來源 | 判定 | 依據 |
| --- | --- | --- | --- |
| C（三份 artifact 仍宣稱全域鎖定優先，與串流優先序實作不符） | R4 finding 1 | **unresolved** | 程式碼與 spec ADDED、spec MODIFIED、design Decisions、design Contract 1、Contract 8、tasks 1.5 敘述與 success 共八處已同步為標記優先，但 `proposal.md` 仍逐字保留串流優先序宣稱 |

Reviewer V 另逐一確認 Round 4 八條 Fix Action 的落地情形：第 1 條為部分落地（`proposal.md` 未同步），其餘七條全部確認落地並附逐字或執行證據。Reviewer V 亦實際執行了相關測試（21 個案例、0 失敗），並重數 Round 4 自報的所有數字（十一個 classify 案例、五個版面斷言、四個 static 入口、版面量測值、`## Impact` 的九個檔案）全部相符。

### Critical

（無）

### Warning

1. `severity`: Warning／`confidence`: 100／`layer`: design／`disposition`: `unresolved-prior`（R4 finding 1，member C）
   - `location`: `proposal.md` `## Proposed Solution` 第一點
   - `summary`: Round 4 把 `classify` 改回標記優先後，proposal 仍逐字保留 Round 3 的串流優先序宣稱「失敗分類則對兩個串流各自的摘要分別判定並以 standard error 優先」。該句在現行實作下為假——`classify` 先跨兩串流檢查鎖定標記、再跨兩串流檢查授權標記，不存在 standard error 優先的分支；Round 4 自己新增的 `testDeviceLockWinsWhenTheAuthorizationMarkerIsInTheOtherStream` 即為直接反例。Round 4 的殘留掃描字串為 `以 standard error 的摘要優先`，未涵蓋 proposal 實際的 `並以 standard error 優先`，故回報 0 而漏抓。此與 R3 finding 5「proposal 是 fix propagation 唯一漏掉的 artifact」為同一模式的第二次重演。
   - `recommendation`: 把該句改為與 spec、design 一致的標記優先措辭；後續殘留掃描改以較短、不含可變修飾語的字串為 pattern。

### 經 filter 丟棄的 findings（confidence < 50，記錄降級 trace）

2. `confidence`: 25／`layer`: design／`disposition`: `fix-introduced`／`introduced_by`: Round 4 finding 5（`exceptionSummary` 改 `trimmingCharacters(in: boxCharacters)`）：`boxCharacters` 只含 ASCII 空白與 tab，並非 `.whitespaces` 的超集，行首尾若帶 U+00A0 等 Unicode 空白將不再被剝除。Reviewer V 自述未觀察到 `rich` 產生此類輸出、僅為理論風險，並明確建議「維持現狀即可，不值得為此改動」。依 confidence filter 丟棄，且採納 reviewer 自身的建議不作變更。

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 1
- 非 blocking triaged finding count: 0
- `critical_gap`: false
- `round_type`: micro

rationale：Reviewer V 以逐字讀檔確認 member C 的修復在九個位置中有八個落地、`proposal.md` 一處未同步，判定 unresolved 並保留於 cumulative blocking set。該筆 confidence 100 且 `disposition` 為 `unresolved-prior`，為 blocking。唯一另一筆 finding confidence 25，經 filter 丟棄並記錄降級 trace。set 中仍有一筆 blocking Warning，因此不得判為 `passed`。

## Fix Actions

- finding 1：把 `proposal.md` `## Proposed Solution` 第一點的分類敘述改為「任一串流摘要命中鎖定標記即分類為鎖定、皆未命中才檢查任一串流是否命中授權標記，使只印在 standard output 的分類標記不致漏判且鎖定不被授權吸收」，與 spec、design、tasks 及實作一致。
- finding 2：依 confidence filter 丟棄，不作變更；降級 trace 如上。

**流程改進**：本輪起殘留掃描改用較短且不含可變修飾語的 pattern。已以 `standard error 優先`、`stderr 優先`、`同時檢視`、`渲染列數`、`IsKeptAsIs`、`/Users/cash`、`原樣保留`、`四個摘要案例`、`十二個案例`、`兩個既有的 switch`、`pure-refactor：本任務` 共十一個 pattern 掃過 artifacts 與程式碼（排除 `reviews/`），全部為 0。

**交叉一致性複核**：主 agent 另就「鎖定優先」宣稱在 proposal、design Decisions、design Contract 1、tasks 1.5、spec ADDED 五處逐一抽出措辭並與 `classify` 的實作對照，五處語意一致且皆為標記優先。此複核針對本 loop 反覆出現的「修復只傳播到部分 artifact」失效模式，於每次跨 artifact 修改後執行。

post-fix mechanical self-check：annotation lint、title identity、identifier cross-grep 通過。

fix 後重跑：`validate` 通過；完整 macOS 測試套件 242 個測試全綠。

無 `未修復：裁判面保護` 記錄。

## Decision

next_round
