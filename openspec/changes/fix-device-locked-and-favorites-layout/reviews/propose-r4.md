# Cash Propose Review — Round 4

## Reviewer Findings

`round_type` 為 full（本 run 第四輪 checkpoint），由 Reviewer A 與 Reviewer B 並行獨立審查，兩者皆對 cumulative blocking set 逐一給出判定。

### Cumulative blocking set 逐條判定

| member | 來源 | Reviewer A | Reviewer B | 合併判定 |
| --- | --- | --- | --- | --- |
| A（task 1.5 的 `red` 宣稱不存在的 oracle） | R3 finding 1 | resolved | resolved | resolved |
| B（delta spec「同時檢視兩個串流」過度宣稱） | R3 finding 2 | resolved | resolved | resolved |

兩位 reviewer 各自以逐字讀檔比對，並手動推演分支對調會使 `testDeviceLockTakesPrecedenceOverAuthorizationOnTheSameLine` 失敗，確認 oracle 有效；`success` 列出的案例逐一在測試檔中找到對應方法。兩個 member 皆以 verified-resolution 離開 cumulative blocking set，set 隨後為空。

### Critical

（無）

### Warning

1. `severity`: Warning／`confidence`: 100／`layer`: design／來源：Reviewer B／`disposition`: `fix-introduced`／`introduced_by`: Round 3 `## Fix Actions` 的 finding 3（`classify` 改為依串流優先序逐一判定）
   - `location`: `design.md` `## Decisions` 分類順序段；`tasks.md` task 1.5 敘述；`specs/ios-device-session/spec.md` MODIFIED requirement 的「裝置螢幕鎖定 MUST NOT 被歸類為授權被拒絕」
   - `summary`: Round 3 把 `classify` 改為串流優先序後，三份 artifact 仍保留改動前的全域「鎖定優先於授權」宣稱，而該宣稱在跨串流時為假。反例：standard error 摘要為 `PairingDialogResponsePendingError: pairing is pending`、standard output 摘要為 `{'Error': 'DeviceLocked'}` 時回傳 `authorizationDenied`，鎖定確實被較寬鬆的授權判定吸收。Round 3 的修復只傳播到 spec ADDED requirement 與 design Contract 1，漏掉其餘三處。
   - `recommendation`: 收斂 artifact 措辭以符合串流優先序，或改回標記優先並讓三處宣稱成立。

### Suggestion

以下為經 filter 降級的非 blocking findings，全部已在本輪一併修復：

2. `confidence`: 100／`layer`: design／Reviewer B／`disposition`: `new`：`lastMeaningfulLine` 的「取最後一個」語意零可證偽覆蓋——走該分支的輸入全部只有一行非雜訊內容，把 `.last` 改成 `.first` 整個測試套件仍會全綠，而 task 1.1 的 `success` 明文把它列為必須涵蓋的案例。Reviewer A 獨立提出同一問題（confidence 75），並另指出測試方法名 `…IsKeptAsIs` 是已撤回的「原樣保留」措辭遺留。依 `location + summary` 合併。
3. `confidence`: 75／`layer`: design／Reviewer A／`disposition`: `new`：ADDED requirement 寫「被分類為鎖定或授權被拒絕時使用者看到該分類的固定指引」，但 MODIFIED requirement 的例外只逐字列舉螢幕鎖定，授權被拒絕仍落在無條件的「顯示該階段修復資訊」規則下，delta 內部互相牴觸。
4. `confidence`: 50／`layer`: text／Reviewer A／`disposition`: `new`：`design.md` `## Decisions` 寫「因為授權判定的關鍵字與鎖定訊息不重疊，先判鎖定可確保鎖定不被吸收」，前提與結論方向相反——若確實不重疊，順序即無可觀察差異。Round 3 已在 task 1.5 的 `red` 修正此因果推論，design 未同步。
5. `confidence`: 50／`layer`: design／Reviewer B／`disposition`: `new`：`noisePatterns` 第三條以 `^` 錨定且假設行首方框字元已被剝除，但 `exceptionSummary` 只做 `.whitespaces` trim，該 pattern 在此路徑結構性地永不命中，兩條路徑對原始碼行號回顯的過濾能力不對等。可觸發條件為輸出在方框未閉合處中斷。
6. `confidence`: 50／`layer`: design／Reviewer B／`disposition`: `new`：版面測試以「渲染列數等於收藏數」作為「可於清單內捲動存取」的證據，但把 `ScrollView` 換成 `.frame(height:).clipped()` 後所有列一樣存在於 view hierarchy，三個斷言全數仍通過，使用者卻只看得到前五筆。該 spec scenario 缺乏可證偽的 oracle。
7. `confidence`: 50／`layer`: design／Reviewer B／`disposition`: `new`：版面測試建立的 suite 名為 `favorites-cap-N`，未帶專案前綴，與同檔 `iPhoneLocationMoveTests-<UUID>` 慣例不一致；helper 建立後第一件事是 `removePersistentDomain`，若該名稱已被他者使用會清空對方資料。
8. `confidence`: 50／`layer`: text／Reviewer B／`disposition`: `new`：`lockedDeviceStderr` fixture 內嵌開發者真實家目錄絕對路徑，是本次改動引入且為 repo 內唯一出現處；該前綴不承載任何斷言價值卻把執行者身分寫進版控。

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 1
- 非 blocking triaged finding count: 7
- `critical_gap`: false
- `round_type`: full

rationale：兩位 reviewer 對兩個既有 member 的判定一致為 resolved，兩者皆離開 cumulative blocking set。Reviewer B 新增一筆 confidence 100 且 `disposition` 為 `fix-introduced` 的 Warning 進入 set 並為 blocking。Reviewer A 與 Reviewer B 對「`lastMeaningfulLine` 取最後一個語意零覆蓋」獨立提出，依 `location + summary` 合併並取較高 confidence；該筆 `disposition` 為 `new`，非 blocking。其餘皆為 `new` 且經 filter 降級為 Suggestion。set 中仍有一筆 blocking Warning，因此不得判為 `passed`。

## Fix Actions

- finding 1：把 `classify` 改回標記優先——任一串流摘要命中鎖定即回傳鎖定，皆未命中才檢查任一串流是否命中授權。此決定不是回退，而是改採較佳的一側：解鎖是完成信任的前提，兩者並存時解鎖仍是正確的下一步，對鎖定裝置給出信任指引會讓使用者卡住。Round 3 finding 3 所憂慮的「standard output 覆寫 standard error」在此改以「顯示來源與分類來源可能不同串流，此為刻意取捨」的方式明文記載於 design Contract 1，並非以 accepted-risks 條目處理。新增 `testDeviceLockWinsWhenTheAuthorizationMarkerIsInTheOtherStream` 與 `testDeviceLockWinsWhenTheLockMarkerIsInStandardError` 涵蓋兩個方向；delta spec 新增「鎖定標記與授權標記分處兩個串流時鎖定優先」scenario；`design.md` `## Decisions` 與 Contract 1、`tasks.md` task 1.5 敘述與 `success` 全部同步。
- finding 2：新增 `testMultiLineOutputWithoutATracebackTakesTheLastMeaningfulLine`，輸入為兩行皆非雜訊的無方框輸出，斷言取到末行。已以暫時把 `.last` 改為 `.first` 的實驗確認該測試會失敗並回報首行，證明其為有效 oracle。`testPlainStderrWithoutATracebackIsKeptAsIs` 更名為 `testSingleLineOutputWithoutATracebackIsUsedAsIs`，移除已撤回的措辭遺留。
- finding 3：MODIFIED requirement 補上「授權被拒絕同為裝置層級失敗，其指引同樣取代該階段的修復資訊」，消除與 ADDED requirement 的牴觸。
- finding 4：`design.md` `## Decisions` 的理由句改寫為與 task 1.5 `red` 一致的說法——現行關鍵字集合互斥使順序無可觀察差異，真正的理由是解鎖為信任的前提，並以構造輸入釘住優先序契約。
- finding 5：`exceptionSummary` 的過濾改為先 `trimmingCharacters(in: boxCharacters)` 再判雜訊，與 `lastMeaningfulLine` 對等，使錨定的原始碼行號回顯 pattern 在兩條路徑皆可命中。
- finding 6：版面測試的「渲染列數」斷言改為在最愛區塊內尋找 documentView 高度大於 clip view 的 `NSScrollView`，並同時斷言收藏數未達門檻時不存在該捲動容器。已以暫時把 `ScrollView` 換成 `.frame(height:).clipped()` 的實驗確認該斷言會失敗，證明其為有效 oracle。`design.md` Contract 10 與 `tasks.md` task 2.3 同步改寫，不再把渲染列數宣稱為捲動可達性的證據。
- finding 7：suite 名改為 `iPhoneLocationMoveTests-favorites-cap-N`，與同檔既有慣例一致。
- finding 8：fixture 的家目錄前綴改為 `/Users/tester/`。已 grep 確認 `iPhoneLocationMove` 與 `iPhoneLocationMoveTests` 下不再出現真實家目錄路徑。

post-fix mechanical self-check 抓到並修復：count-consistency——task 1.5 的 `success` 原寫「十二個案例」，但其中「無 traceback 的多行輸出取最後一個有意義的行」走的是 `summarize` 而非 `classify`，實際 classify 案例為十一個。已改為「十一個 classify 案例」，並把該多行案例移入 task 1.1 的 `summarize` 案例清單。annotation lint、title identity、殘留舊措辭掃描（`以 standard error 的摘要優先`、`同時檢視`、`渲染列數`、`IsKeptAsIs`、真實家目錄路徑）全部為 0。

fix 後重跑：`validate` 通過；完整 macOS 測試套件 242 個測試全綠；Python protocol 測試 14 個通過。

無 `未修復：裁判面保護` 記錄。

## Decision

next_round
