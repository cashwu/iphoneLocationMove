## ADDED Requirements

### Requirement: 裝置準備失敗細節只保留可行動摘要

系統 SHALL 在把 `pymobiledevice3` 的非零離開結果轉為 typed 失敗前，先產生單行的失敗細節。該細節 MUST 只包含可行動的例外摘要，MUST NOT 包含與本次失敗無關的執行環境警告、traceback 標題、frame 標頭或原始碼行號回顯。standard error 與 standard output SHALL 各自獨立摘要，MUST NOT 接合為同一個句子；standard output 只在 standard error 沒有可用內容時作為來源。例外摘要因輸出寬度而折行為多行時 SHALL 接合為單行。輸出不含 traceback 結構時 SHALL 取最後一個有意義的錯誤行。可用內容全為雜訊時 SHALL 退回含離開碼的固定訊息。

失敗細節 SHALL 設長度上限，超出時截斷。失敗分類 MUST 在截斷前的細節上進行，使長輸出不致讓分類標記被截斷而漏判；分類 MUST 對 standard error 與 standard output 各自產生的摘要分別判定，使只出現在其中一個串流摘要上的分類標記不致漏判。任一串流摘要出現裝置螢幕鎖定標記時 SHALL 分類為裝置螢幕鎖定，且此判定 SHALL 優先於任一串流的授權標記——解鎖是完成信任的前提，兩者並存時解鎖指引仍是正確的下一步，而信任指引會讓鎖定的裝置卡住。顯示用細節仍只取單一串流。分類標記若落在該串流被雜訊過濾或未被選為摘要的行上，則不在分類的觀察範圍內。當該細節未被分類為裝置螢幕鎖定或授權被拒絕時，截斷後的細節 SHALL 成為該階段 prerequisite 失敗顯示給使用者的訊息；被分類為裝置螢幕鎖定或授權被拒絕時，使用者看到的是該分類本身的固定指引而非此細節。

#### Scenario: 只保留 traceback 之後的例外摘要

- **GIVEN** `pymobiledevice3` 以非零離開碼結束
- **AND** 其 standard error 開頭為 `NotOpenSSLWarning` 警告、其後為方框式 traceback、最後為例外摘要
- **WHEN** 系統產生失敗細節
- **THEN** 細節只包含該例外摘要
- **AND** 細節不含 `NotOpenSSLWarning`、traceback 標題與任何原始碼行號回顯

#### Scenario: 折行的例外摘要接合為單行

- **GIVEN** 例外摘要因輸出寬度在空白處折成兩行
- **WHEN** 系統產生失敗細節
- **THEN** 兩行接合為單一完整句子，而非只取其中一行

#### Scenario: standard output 不併入 standard error 的例外摘要

- **GIVEN** standard error 含完整的方框式 traceback 與例外摘要
- **AND** standard output 另有兩行與該例外無關的輸出
- **WHEN** 系統產生失敗細節
- **THEN** 細節只包含 standard error 的例外摘要
- **AND** 細節不含任何 standard output 的內容

#### Scenario: standard error 無可用內容時改用 standard output

- **GIVEN** standard error 為空
- **AND** standard output 有一行普通錯誤文字
- **WHEN** 系統產生失敗細節
- **THEN** 細節為該行錯誤文字

#### Scenario: 無 traceback 時取最後一個有意義的錯誤行

- **GIVEN** standard error 不含方框式 traceback
- **WHEN** 系統產生失敗細節
- **THEN** 細節為輸出中最後一個非雜訊行

#### Scenario: 可用內容全為雜訊時退回離開碼

- **GIVEN** `pymobiledevice3` 以離開碼 3 結束
- **AND** 其輸出只有執行環境警告，沒有任何例外摘要
- **WHEN** 系統產生失敗細節
- **THEN** 細節為指明該離開碼的固定訊息

#### Scenario: 分類標記只出現在 standard output 時仍能分類

- **GIVEN** standard error 另有一行非雜訊的錯誤文字，且該行不含任何分類標記
- **AND** 表示裝置螢幕鎖定的標記出現在 standard output 的摘要行上
- **WHEN** 系統對該失敗分類
- **THEN** 系統 SHALL 分類為裝置螢幕鎖定

#### Scenario: 鎖定標記與授權標記分處兩個串流時鎖定優先

- **GIVEN** 其中一個串流的摘要含授權標記
- **AND** 另一個串流的摘要含裝置螢幕鎖定標記
- **WHEN** 系統對該失敗分類
- **THEN** 系統 SHALL 分類為裝置螢幕鎖定
- **AND** 此結果 MUST NOT 因兩個標記分處哪一個串流而不同

#### Scenario: 超過長度上限的細節被截斷

- **GIVEN** 例外摘要長度超過細節的長度上限
- **WHEN** 系統產生要顯示給使用者的細節
- **THEN** 細節被截斷至上限並以省略記號結尾

#### Scenario: 分類標記位於長度上限之後仍能分類

- **GIVEN** 例外摘要長度超過細節的長度上限
- **AND** 表示裝置螢幕鎖定的標記出現在長度上限之後的位置
- **WHEN** 系統對該失敗分類
- **THEN** 系統 SHALL 仍將其分類為裝置螢幕鎖定
- **AND** 系統 MUST NOT 因截斷而退回該階段的 prerequisite 失敗

##### Example: 鎖定裝置的實際輸出

- 輸入 standard error 依序為：`urllib3/__init__.py:35: NotOpenSSLWarning: ...`、`warnings.warn(`、方框式 traceback、`PyMobileDevice3Exception: command ReceiveBytes failed with: {'Error':`、`'DeviceLocked'}`
- 產生的失敗細節為：`PyMobileDevice3Exception: command ReceiveBytes failed with: {'Error': 'DeviceLocked'}`
- 該細節接著依「裝置 prerequisite 準備順序」被分類為裝置螢幕鎖定，因此使用者看到的是解鎖指引，而非此細節本身

## MODIFIED Requirements

### Requirement: 裝置 prerequisite 準備順序

系統 SHALL 依序完成 runtime probe、USB device selection、pairing／trust、Developer Mode、DDI、tunnel 與 DVT helper readiness；任一步失敗時 MUST 停止後續準備並顯示該階段的修復資訊。

在透過 `pymobiledevice3` CLI 執行的階段（USB device selection、pairing／trust、Developer Mode 與 DDI）中，當失敗原因是 iPhone 螢幕鎖定時，系統 SHALL 改為顯示裝置層級的解鎖指引，而非該階段的修復資訊——鎖定可能發生在這些階段中的任一個但修復動作相同；此時系統仍 MUST 停止後續準備。授權被拒絕同為裝置層級失敗，其指引同樣取代該階段的修復資訊。裝置螢幕鎖定 MUST NOT 被歸類為授權被拒絕，也 MUST NOT 被歸類為 DDI 準備失敗。鎖定判定 MUST 涵蓋裝置回傳的原始鎖定錯誤字串與其包裝後的例外名稱兩種形式。

tunnel 與 DVT helper readiness 透過 privileged helper 與 helper 程序執行而非 `pymobiledevice3` CLI，其鎖定分類不在此 requirement 的涵蓋範圍。

#### Scenario: 尚未信任 Mac

- **WHEN** selected iPhone 尚未與 Mac 配對或信任
- **THEN** 系統 SHALL 要求使用者解鎖 iPhone 並完成信任
- **AND** 系統 MUST NOT 嘗試開始定位 session

#### Scenario: Developer Mode 未開啟

- **WHEN** selected iPhone 的 Developer Mode 未開啟
- **THEN** 系統 SHALL 顯示 iOS 設定路徑與重新啟動需求
- **AND** 系統 MUST NOT 跳過此檢查

#### Scenario: DDI 無法準備

- **WHEN** DDI mount 未成功且不是 already-mounted 結果
- **THEN** 系統 SHALL 顯示 DDI 準備失敗
- **AND** 系統 MUST NOT 把 device session 標記為 ready

#### Scenario: 螢幕鎖定導致 DDI 無法掛載

- **GIVEN** selected iPhone 已信任 Mac 且 Developer Mode 已開啟
- **AND** iPhone 螢幕處於鎖定狀態
- **WHEN** 系統嘗試掛載 DDI 而裝置以鎖定為由拒絕
- **THEN** 系統 SHALL 顯示要求解鎖 iPhone 並保持螢幕開啟的指引
- **AND** 系統 MUST NOT 顯示 DDI 準備失敗或確認 Xcode 版本支援的指引
- **AND** 系統 MUST NOT 把 device session 標記為 ready

#### Scenario: 鎖定發生在 trust 階段

- **GIVEN** iPhone 螢幕處於鎖定狀態
- **WHEN** 準備流程在 pairing／trust 階段因裝置鎖定而失敗
- **THEN** 系統 SHALL 顯示與 DDI 階段相同的解鎖指引
- **AND** 系統 MUST NOT 顯示該階段原本的修復資訊

#### Scenario: 原始鎖定錯誤字串同樣被辨識

- **GIVEN** 失敗細節只含裝置回傳的原始鎖定錯誤字串，而非其包裝後的例外名稱
- **WHEN** 系統對該失敗分類
- **THEN** 系統 SHALL 分類為裝置螢幕鎖定
