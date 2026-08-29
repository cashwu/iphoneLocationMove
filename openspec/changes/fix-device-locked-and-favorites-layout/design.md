## Context

裝置準備透過 LivePymobiledeviceBoundary 以子行程呼叫 pymobiledevice3 CLI，離開碼非零時把輸出轉為 typed 失敗，再由 DeviceFailurePresentation 轉成標題、訊息與復原動作。目前失敗細節取整段 standard error 與 standard output，這在 pymobiledevice3 上有兩個結構性問題：輸出開頭固定帶一段與失敗無關的 NotOpenSSLWarning，且例外訊息被包在 rich 繪製的方框式 traceback 之後、並會在終端寬度邊界折行。

Mac 端地圖側欄以單一 ScrollView 垂直堆疊多個區塊。「我的最愛」目前排在預覽控制之後、端點與路線控制之前，也就是在 iPhone 定位控制之前，且以無上限的方式逐筆列出收藏。最愛的持久化由 FavoritesStore 透過 UserDefaults 完成，其 initializer 目前對 UserDefaults 提供預設值。

以 hosting view 量測（視窗 900x620，即 App 宣告的最小尺寸）取得的實際數字如下，作為本設計的依據：

- 零筆最愛時「設定位置」按鈕底緣位於 597.5，可視高度 620，餘裕 22.5。
- 最愛每列高 16，列間距 6。第一筆收藏使區塊標題、區塊間距與一列一併出現，其後內容一次下移 54；其後每多一筆再下移 22。
- 一筆最愛時「設定位置」底緣 651.5，已超出可視範圍；八筆時 805.5。以上皆為實測值。

## Goals / Non-Goals

Goals：

- 讓裝置準備失敗時呈現的訊息只包含可行動的例外摘要，不含無關警告與 traceback 結構。
- 讓「裝置螢幕鎖定」成為獨立且可辨識的失敗，與授權被拒絕、DDI 準備失敗區分開來。
- 讓「設定位置」在最小視窗尺寸下的位置不受收藏數量影響。
- 讓最愛清單的高度有上限，側欄不因收藏累積而無上限增長。
- 讓側欄的 view 層測試不再依賴或寫入執行者的真實偏好設定。

Non-Goals：

- 不消除 NotOpenSSLWarning 的成因，只在訊息呈現層過濾。
- 不變更 DDI 掛載流程與 already-mounted 判定。
- 不重新設計側欄資訊架構或視覺樣式。
- 不新增最愛數量上限，不變更最愛儲存格式。

## Decisions

**以 traceback 收框線為界抽取例外摘要，而非取最後一行。**
rich 會在寬度邊界折行，因此例外訊息常橫跨多行，單取最後一行會得到殘句。改為找出輸出中最後一個「整行僅由方框繪製字元與空白組成」的行，取其後的所有非空白行，過濾雜訊後以單一空白接合。rich 的折行發生在空白處，因此以單一空白接合可還原原句。沒有方框時退回逐行過濾後取最後一個有意義的行；全部都是雜訊時退回帶離開碼的固定訊息。摘要長度上限 400 字元，超出時截斷並附省略號。

**雜訊判定採用結構特徵而非固定字串清單。**
過濾條件為：以 warnings.warn 開頭的續行、含 traceback 標題的行、frame 標頭（路徑加行號後接識別字）、Python 警告行（路徑加行號後接以 Warning 結尾的類別名），以及原始碼行號回顯（可選的指標字元後接數字再接欄位分隔線）。這樣新的警告類別或不同的 frame 內容都不需要再改清單。

**裝置螢幕鎖定是裝置層級失敗，不是 prerequisite 階段失敗。**
新增 typed 失敗值而非沿用 prerequisiteFailed，因為鎖定可能發生在 USB device selection、trust、Developer Mode 或 DDI 這四個透過 pymobiledevice3 CLI 執行的階段中的任一個，但修復動作都相同。失敗分類順序為先判定鎖定、再判定授權，最後才落入該階段的 prerequisite 失敗，且鎖定判定跨兩個串流摘要一併進行後才輪到授權判定。理由不是關鍵字互斥——以 pymobiledevice3 目前的訊息而言兩組關鍵字確實不重疊，順序在現行集合下無可觀察差異——而是兩者並存時解鎖才是正確的下一步：解鎖是完成信任的前提，對鎖定的裝置給出信任指引會讓使用者卡住。此優先序以刻意構造的輸入釘住，避免日後關鍵字集合擴張時靜默翻轉。

**以區塊順序調整解決可視性，以高度上限解決增長。**
兩者解決不同問題且缺一不可。實測顯示零筆最愛時餘裕僅 22.5，因此任何仍讓最愛排在 iPhone 定位控制之前的方案（包含只顯示一列的高度上限）都無法讓「設定位置」回到可視範圍；而只調整順序則無法阻止側欄隨收藏累積而無上限增長。因此把「我的最愛」移到 iPhone 定位控制之後，並在收藏超過門檻時讓清單在固定高度內自行捲動。

**高度上限只在超過門檻時套用。**
ScrollView 在其捲動軸向是貪婪的，若無條件套用高度上限，收藏很少時也會佔滿該高度並留下空白。因此在收藏數未超過門檻時維持原本的直接列出，超過時才包入固定高度的 ScrollView。門檻為 5 筆，固定高度 104，由實測的列高 16 與列間距 6 推得（5 乘 16 加 4 乘 6）。此高度在系統字級放大時會顯示較少列並繼續捲動，不會破版。

**移除 UserDefaults 預設值而非只修測試。**
只把測試改成注入隔離 suite 可以讓測試通過，但預設值本身讓「不小心寫到真實偏好設定」永遠只差一個無參數建構；而該型別的 toggle、rename 與 remove 都會寫回同一個 domain。移除預設值使呼叫端必須明示來源，由型別系統防止同類問題再次發生。

## Implementation Contract

1. iPhoneLocationMove/Device/PymobiledeviceAdapter.swift 新增 internal 層級的 PymobiledeviceFailureSummary，提供 classify、summarize、isDeviceLockedFailure 與 isAuthorizationFailure 四個 static 入口。內部先產生未截斷的失敗細節：standard error 與 standard output 各自獨立摘要，standard error 沒有可用內容時才改用 standard output，兩者不進入同一次接合。summarize 是對外暴露的測試接縫，與 classify 共用同一段細節產生與截斷邏輯；production 端的顯示用截斷由 classify 內部產生，不經 summarize。classify 接受 standard error、standard output、離開碼與 prerequisite 階段：分類判定對兩個串流各自的未截斷摘要分別進行：任一串流摘要命中鎖定即回傳鎖定，皆未命中才檢查任一串流是否命中授權，使只印在 standard output 的標記不致漏判且鎖定不被授權吸收；顯示用細節仍只取單一串流以避免拼接，因此顯示來源與分類來源可能不同串流，此為刻意取捨。分類的觀察範圍是各串流收斂後的摘要行，不是串流全文。依序判定裝置鎖定、授權被拒絕，最後回傳帶該階段與截斷後細節的 prerequisite 失敗。isAuthorizationFailure 沿用既有的 not trusted、pairing、permission denied 與 user denied 判定。isDeviceLockedFailure 判定 devicelocked、device is locked、passwordrequired 與 passwordprotected，後者是 lockdown 回傳的原始錯誤字串。兩個判定函式的字串比對不分大小寫；摘要的雜訊判定依 pymobiledevice3 固定的輸出樣式做大小寫敏感比對。
2. LivePymobiledeviceBoundary 中執行 pymobiledevice3 的私有 run 方法，在離開碼非零時直接丟出 PymobiledeviceFailureSummary.classify 的結果。分類順序本身住在 classify 這個 pure function 上而非 private actor 內，因此可被直接測試；原先的私有 failureDetail 與 isAuthorizationFailure 由新型別取代。
3. iPhoneLocationMove/Device/DeviceLocationClient.swift 的 DeviceLocationError 新增 deviceLocked case，DeviceRecoveryAction 新增 unlockDevice case。DeviceFailurePresentation 對 deviceLocked 回傳的標題須可與既有標題區分、訊息須指示解鎖 iPhone 並保持螢幕開啟、復原動作為 unlockDevice。既有帶 default 分支的 switch 會吸收新 case，因此不需修改。
4. iPhoneLocationMove/Features/Favorites/FavoritesStore.swift 的 initializer 移除 UserDefaults 預設值。iPhoneLocationMove/ContentView.swift 與 iPhoneLocationMove/App/iPhoneLocationMoveApp.swift 的建構點改為明示傳入 standard domain。
5. iPhoneLocationMove/Features/Map/LocationMapView.swift 把最愛區塊的組合位置由預覽控制之後移到 iPhone 定位控制之後，位置在工作區訊息與 Mac 定位訊息之前。最愛區塊開頭加入分隔線以與前一區塊區隔。
6. 同一檔案的最愛區塊在收藏數超過 5 時，把列的堆疊包入固定高度 104 的 ScrollView；未超過時直接列出。列的堆疊抽出為獨立的 view 屬性供兩條路徑共用，測試用的區域標記仍套在最愛區塊最外層。
7. iPhoneLocationMoveTests/ContentViewTests.swift 的地圖 hosting view 建構輔助方法，其最愛儲存體參數預設值改為使用一次性隔離 suite；另一處直接建構最愛儲存體的測試同樣改用隔離 suite。
8. iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift 新增針對 PymobiledeviceFailureSummary 的測試，涵蓋：鎖定 traceback 的摘要結果、鎖定分類、無 traceback 的一般錯誤輸出、僅含警告時的離開碼退回、授權判定不被新分類吸收、standard output 不被接到 standard error 例外之後、standard error 無內容時改用 standard output、超過長度上限時截斷並以省略記號結尾、分類標記落在長度上限之後仍能分類為鎖定、lockdown 原始鎖定錯誤字串被辨識，classify 在 trust 與 developerMode 階段分別回傳鎖定、授權與帶階段的 prerequisite 失敗、pairing 的方框式 traceback 仍回傳授權被拒絕，鎖定標記只出現在 standard output 時仍回傳鎖定、同一行同時含鎖定與授權標記時鎖定優先、鎖定與授權標記分處兩個串流時無論方向皆鎖定優先，無 traceback 的多行輸出取最後一個有意義的行、未分類失敗的 prerequisiteFailed message 於超過上限時被截斷（涵蓋 production 端截斷，summarize 路徑無法涵蓋），以及三條雜訊規則各自可證偽——方框未閉合時 frame 標頭與原始碼行號回顯不得進入摘要、輸出在 traceback 標題後截斷時標題不得成為摘要。
9. iPhoneLocationMoveTests/DeviceFailurePresentationTests.swift 把 deviceLocked 納入既有的標題相異性檢查，並新增針對其復原動作與訊息內容的斷言。
10. iPhoneLocationMoveTests/ContentViewTests.swift 新增側欄回歸測試，驗證在收藏數遠超門檻時「設定位置」仍位於側欄可視範圍內、最愛區塊高度與剛超過門檻時相同、該情形下最愛區塊內存在其 documentView 高於 clip view 的捲動容器因此所有收藏可捲動存取，而收藏數未達門檻時不存在該捲動容器，且收藏數未達門檻時區塊高度小於剛超過門檻時的高度以證明未預留額外空白。該測試建立的隔離 UserDefaults suite 於測試結束時清除其持久化內容。

## Risks / Trade-offs

- 摘要規則以結構特徵過濾雜訊，若 pymobiledevice3 未來改變輸出樣式（例如停用 rich 或改變方框字元），摘要會退回逐行過濾路徑。該路徑仍會產生可讀的單行結果，最壞情況是保留較多脈絡而非產生錯誤訊息。
- 摘要仍可能包含裝置識別碼或使用者家目錄絕對路徑等來自例外訊息的內容，且這些內容確實會落地：DeviceSetupStore 的 connect 失敗路徑會把 typed 失敗（含 prerequisiteFailed 的 message）寫入 diagnostic metadata，經 DiagnosticLogger 存入使用者的 diagnostic.jsonl。本次相對於既有行為是**減少**寫入量——舊的 failureDetail 會把整段 stderr 與 stdout 寫入，新摘要只寫單行——因此不新增持久化路徑，但也未新增遮蔽。維持不遮蔽是本次的取捨；若要收斂該路徑，需另行處理遮蔽並以含敏感值的 fixture 驗證。此外，deviceLocked 與 authorizationDenied 兩個分類都不攜帶 associated message，因此一旦分類命中，該次失敗寫入診斷紀錄的內容只剩分類名稱，原始摘要完全不落地。這對隱私是進一步收斂，但也意味著分類誤判時事後無從由診斷紀錄追查原因；本次接受此取捨，不另存未分類摘要。
- 以單一空白接合折行是基於 rich 在空白處折行的常見情形。rich 對超過寬度且不含空白的單一 token（例如 UDID 或長 URL）會做硬折，此時接合會在 token 中間插入一個原本不存在的空白，使該識別碼在訊息中失真。此限制影響可讀性而非分類正確性，因為分類比對的關鍵字本身不含空白。
- 固定高度 104 由預設字級下的實測列高推得。系統字級放大時可見列數會減少，清單仍可捲動，不影響可用性，但顯示的列數會少於五筆。
- 把「我的最愛」移到 iPhone 定位控制之後，使它與搜尋、預覽等選點相關區塊在版面上分離。取捨結果是優先保證裝置主要動作的位置穩定。
- 移除 UserDefaults 預設值是 source-breaking 的介面變更，任何新的呼叫端都必須明示來源。這正是本次要達成的效果。
