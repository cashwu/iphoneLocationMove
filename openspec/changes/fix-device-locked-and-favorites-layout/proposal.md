## Summary

修正兩個各自獨立、但都在這次連接 iPhone 的診斷過程中暴露的缺陷：裝置準備失敗時把整包 Python traceback 當成錯誤訊息並誤導成 DDI 問題；以及 Mac 端地圖側欄的「我的最愛」會把 iPhone 定位控制擠出可視範圍，且其 layout 測試會讀取執行者的真實偏好設定。

## Motivation

使用者連接 iPhone 時看到一整頁紅色 Python traceback，標題為「Developer Disk Image 無法準備」，並建議「確認 Xcode 支援此 iOS 版本」。實測 mounter auto-mount 後確認真正原因是 iPhone 螢幕鎖定，裝置回傳 DeviceLocked；解鎖後 DDI 立即掛載成功。錯誤訊息把使用者的診斷方向帶往完全錯誤的地方。

兩個可獨立觀察的缺陷造成這個結果：

- 失敗細節直接取用整段 standard error 與 standard output。pymobiledevice3 的 stderr 開頭是與本次失敗無關的 NotOpenSSLWarning，其後是 rich 繪製的 traceback 方框；真正可行動的例外摘要被淹沒在最下方，且該摘要本身會在空白處折行，單看最後一行只會得到殘句。
- 授權失敗判定只涵蓋 not trusted、pairing、permission denied 與 user denied 四種字樣，DeviceLocked 落在其外，因此被歸入 developerDiskImage 階段的 prerequisite 失敗，顯示出與真正原因無關的修復指引。

側欄部分則是在追查一個穩定失敗的 layout 測試時發現的：

- 地圖側欄的 hosting view 測試以不帶參數的方式建構 FavoritesStore，而該型別的 initializer 預設使用 UserDefaults.standard，也就是 App 本尊的偏好設定域。測試因此渲染執行者本人已儲存的最愛，測試結果取決於個人資料而非程式碼；在乾淨機器上會通過，在有存過最愛的機器上會失敗。該型別的 toggle、rename 與 remove 都會寫回同一個 domain，所以同樣的預設值也讓測試具備覆寫真實資料的能力。
- 「我的最愛」區塊以無上限的方式逐筆列出所有收藏，且排在 iPhone 定位控制之前。實測在 App 的最小視窗尺寸 900x620 下，零筆最愛時「設定位置」按鈕底緣位於 597.5，距離 620 只剩 22.5 點。第一筆收藏會讓區塊標題、區塊間距與一列一併出現，使其後內容一次下移 54 點，因此第一筆收藏就會把這個主要動作推出可視範圍；其後每多一筆再下移 22 點，八筆時該按鈕底緣已達 805.5。

## Proposed Solution

裝置失敗訊息：

- 新增一個失敗摘要規則，從 pymobiledevice3 的輸出中取出 rich traceback 收框線之後的例外摘要，並把該摘要因寬度而折行的多行重新接回單行；過濾 NotOpenSSLWarning 這類與失敗無關的警告、traceback 標題、frame 標頭與原始碼行號回顯。沒有 traceback 結構時取最後一個有意義的錯誤行；全部都是雜訊時退回帶離開碼的固定訊息。standard error 與 standard output 各自獨立摘要：顯示用細節只取單一串流，standard output 只在 standard error 沒有可用內容時作為顯示來源；失敗分類則對兩個串流各自的摘要分別判定，任一串流摘要命中鎖定標記即分類為鎖定、皆未命中才檢查任一串流是否命中授權標記，使只印在 standard output 的分類標記不致漏判且鎖定不被授權吸收。摘要設定長度上限，且失敗分類在截斷前的細節上進行。
- 新增一個代表「裝置螢幕鎖定」的 typed 失敗與對應的復原動作，並在失敗分類時優先於授權判定。此失敗屬於裝置層級而非特定 prerequisite 階段，因此 USB device selection、trust、Developer Mode 與 DDI 這四個透過 pymobiledevice3 CLI 執行的階段，任一遇到鎖定都會得到同一則「請解鎖 iPhone 並保持螢幕開啟」的指引。

最愛與側欄版面：

- 移除 FavoritesStore initializer 的 UserDefaults 預設值，改由呼叫端明示。App 的兩個建構點明示使用 standard domain；測試改用一次性的隔離 suite。
- 將「我的最愛」區塊移到 iPhone 定位控制之後，使「設定位置」的位置不再受收藏數量影響；同時在收藏超過五筆時讓清單在固定高度內自行捲動，避免側欄無上限增長。

## Non-Goals

- 不處理 NotOpenSSLWarning 的成因。該警告來自 runtime 虛擬環境建立在 Xcode 內建的 Python 3.9（LibreSSL）之上，屬於獨立的 runtime 環境議題，本次只在訊息呈現層過濾它。
- 不變更 DDI 掛載流程本身，也不變更 already-mounted 的判定方式；實測確認該路徑離開碼為 0，行為正確。
- 不重新設計側欄的資訊架構或視覺樣式，只調整會影響主要動作可視性的區塊順序與清單高度。
- 不處理本機 Apple Development 簽章憑證過期，該問題已由使用者自行更新憑證解決。
- 不處理 tunnel 與 DVT helper readiness 兩個階段的鎖定分類。這兩者透過 privileged helper 與 helper 程序執行而非 pymobiledevice3 CLI，錯誤來源與轉換路徑不同；本次的鎖定分類只涵蓋走 CLI 的階段。
- 不新增最愛數量上限，也不變更最愛的儲存格式。

## Alternatives Considered

- 只替最愛清單加高度上限而不調整區塊順序：實測顯示零筆最愛時餘裕僅 22.5 點，即使只顯示一列，區塊高度 38 點加上區塊間距 16 點仍會使其後內容下移 54 點而超出，因此高度上限單獨無法讓「設定位置」回到可視範圍。已改為區塊順序調整搭配高度上限。
- 在既有 layout 測試的第一個斷言前加入捲動：能讓測試轉綠，但會讓測試繼續讀取執行者的真實偏好設定，只是把隔離缺陷藏起來，收藏增加後仍會再次失敗。已否決。
- 把 DeviceLocked 併入既有的授權被拒絕失敗：兩者的修復動作不同，鎖定只需解鎖螢幕而非重新信任或核准 helper，合併會再次給出錯誤指引。已否決。
- 僅取 stderr 最後一行作為摘要：rich 會在寬度邊界折行，最後一行常是殘句，無法穩定表達失敗原因。已改為以收框線為界重新接合。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- ios-device-session：裝置準備失敗的訊息內容規則，以及裝置螢幕鎖定的獨立失敗分類與復原指引。
- favorite-places：最愛清單在側欄的位置與高度上限，以及最愛儲存體的 UserDefaults 來源必須由呼叫端明示。

## Impact

- Affected specs:
  - openspec/specs/ios-device-session/spec.md
  - openspec/specs/favorite-places/spec.md
- Affected code:
  - New:
    - （無）
  - Modified:
    - iPhoneLocationMove/Device/PymobiledeviceAdapter.swift
    - iPhoneLocationMove/Device/DeviceLocationClient.swift
    - iPhoneLocationMove/Features/Favorites/FavoritesStore.swift
    - iPhoneLocationMove/Features/Map/LocationMapView.swift
    - iPhoneLocationMove/ContentView.swift
    - iPhoneLocationMove/App/iPhoneLocationMoveApp.swift
    - iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift
    - iPhoneLocationMoveTests/DeviceFailurePresentationTests.swift
    - iPhoneLocationMoveTests/ContentViewTests.swift
  - Removed:
    - （無）
