# Cash Propose Review — Round 6

## Reviewer Findings

`round_type` 為 micro，由單一 Reviewer V 對 cumulative blocking set 做 delta verification。本輪為本 run 的輪數上限。

### Cumulative blocking set 逐條判定

| member | 來源 | 判定 | 依據 |
| --- | --- | --- | --- |
| C（分類優先序宣稱與實作不一致） | R4 finding 1 | **resolved** | 「標記優先」宣稱在全部九個位置與實作逐字一致；Reviewer V 另以對調 `classify` 兩個分支的實驗確認三個優先序案例會失敗，證明非空頭宣稱 |

verified-resolution 移除紀錄：member C 由 Reviewer V 於本輪確認解決並附九處逐字證據與 oracle 有效性實驗，離開 cumulative blocking set。set 隨後為空。

Reviewer V 亦確認 Round 5 的 Fix Action 已落地，Round 1／3／4／5 的失效模式（Fix Action 未落地、`proposal.md` 漏傳播、宣稱涵蓋大於實際 oracle）本輪均未於既有項目重演；另實際執行完整測試套件與四組破壞實驗，並複核全部數量宣稱。

### Critical

（無）

### Warning

以下兩筆 `disposition` 皆為 `new`，依規則為非 blocking，但均為 confidence 100 且經 Reviewer V 以實驗證實，故本輪一併修復而非僅記 triage note。

1. `severity`: Warning／`confidence`: 100／`layer`: design／`disposition`: `new`
   - `location`: `specs/ios-device-session/spec.md` 截斷 scenario；`design.md` Contract 1；`tasks.md` task 1.1 與 1.2 的 `success`；`PymobiledeviceAdapter.swift` 的 `classify`
   - `summary`: 顯示用截斷在 production 路徑上零 oracle。Contract 1 自承「production 端的顯示用截斷由 classify 內部產生，不經 summarize」，而 spec scenario 的 WHEN 正是「系統產生要顯示給使用者的細節」；但唯一的截斷測試走 `summarize`。把 `classify` 的 `truncated(detail)` 改為 `detail` 後測試仍全綠。
   - `recommendation`: 新增以 `classify` 為入口、斷言 `prerequisiteFailed` message 長度與省略記號的案例。

2. `severity`: Warning／`confidence`: 100／`layer`: design／`disposition`: `new`
   - `location`: `specs/ios-device-session/spec.md` ADDED requirement 的 MUST NOT 與其首個 scenario；`design.md` `## Decisions` 雜訊判定段；`PymobiledeviceAdapter.swift` 的 `isNoise` 與 `noisePatterns`
   - `summary`: 五條雜訊規則中的 traceback 標題、frame 標頭與原始碼行號回顯三條零 oracle。唯一的 traceback fixture 中這些行全部位於最後一條方框邊界之前，被 `exceptionSummary` 的結構切割排除，因此相關斷言是結構性成立、與雜訊過濾無關。同時刪除三條規則後測試仍全綠。連帶使 Round 4 finding 5 的修復（`exceptionSummary` 改用 `boxCharacters` trim）也無任何測試保護。
   - `recommendation`: 新增能讓每條規則各自可失敗的 fixture。

### Suggestion

3. `confidence`: 50／`layer`: text／`disposition`: `new`：階段數量宣稱不一致。spec MODIFIED requirement 定為四個 CLI 階段（USB device selection、pairing／trust、Developer Mode、DDI），但 `proposal.md` 與 `design.md` 都只列三個，少列 `usbSelection`。已核對 `run(` 的四個呼叫端，實作確為四個階段，spec 正確。

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 0
- 非 blocking triaged finding count: 3
- `critical_gap`: false
- `round_type`: micro

rationale：唯一的 cumulative blocking set member C 經 Reviewer V 以九處逐字證據與 oracle 有效性實驗確認解決並移出 set，set 為空。本輪三筆 findings 的 `disposition` 皆為 `new`，依規則全部非 blocking——主 agent 已逐一檢視其是否位於本 loop 的 fix-touched 位置，findings 1 與 2 針對的是 Round 1 建立測試時即存在的涵蓋缺口而非任何 fix action 引入，finding 3 的階段列舉自 Round 1 proposal 起即為三個且未被任何 fix action 觸及，故 `new` 標記正確，無需修正為 `fix-introduced`。post-filter cumulative blocking set 無 blocking Critical 亦無 blocking Warning，pass 條件成立。

## Fix Actions

三筆非 blocking findings 全部修復（非僅記 triage note），其中兩筆的 oracle 有效性以破壞實驗逐一確認：

- finding 1：新增 `testUnclassifiedFailureTruncatesTheMessageItShows`，以 `classify` 為入口、輸入 500 字元無分類標記的 stderr，斷言回傳 `prerequisiteFailed` 且 stage 正確、message 長度 401、以省略記號結尾。已以移除 `classify` 內 `truncated(detail)` 的實驗確認會產生 2 個失敗。Contract 8 與 task 1.5 的 `success` 同步（classify 案例數 11 改為 12，已與實測呼叫數核對相符）。
- finding 2：首次嘗試的 fixture 無效——把 scaffolding 置於例外行之前，而 `lastMeaningfulLine` 自尾端往前取第一個非雜訊行，前置行根本不被檢視，該 fixture 對雜訊規則是同義反覆；以逐一移除三條規則的實驗確認失敗數皆為 0 後撤換。改以兩個能讓規則實際生效的 fixture：其一為方框未閉合（輸出中途截斷）的 traceback，使最後一條邊界為內部空白框線、tail 仍帶 frame 標頭與行號回顯；其二為輸出在 traceback 標題行之後即截斷，使標題成為最後一個候選行。重測結果為移除 title、frame、echo 三條規則各自產生 1 個失敗，三條規則皆可證偽。Contract 8 與 task 1.1 的 `success` 同步。
- finding 3：`proposal.md` 與 `design.md` 的階段列舉補上 USB device selection，與 spec 及實作的四個 CLI 階段一致。

post-fix mechanical self-check：annotation lint、title identity 通過；count-consistency 複核 classify 案例數宣稱與實測皆為 12；階段列舉在 proposal、design、spec 三處一致；殘留掃描以七組短 pattern 掃過 artifacts 與程式碼（排除 `reviews/`）全部為 0。

fix 後重跑：`validate` 通過；完整 macOS 測試套件 245 個測試全綠；Python protocol 測試 14 個通過。

無 `未修復：裁判面保護` 記錄。

## Decision

passed
