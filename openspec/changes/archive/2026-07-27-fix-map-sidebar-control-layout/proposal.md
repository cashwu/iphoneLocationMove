## Summary

修正地圖控制欄在加入「到 Mac 位置」與「Reset」後出現的按鈕重疊、寬度不一致與群組跑版。所有側欄操作按鈕 SHALL 使用一致且可預期的對齊與尺寸規則，DEBUG 測試 marker 亦不得出現在畫面或參與布局。

## Motivation

目前 `LocationMapView` 將新按鈕直接插入側欄根 `VStack`，既有按鈕則分散在多個 `VStack`／`HStack` 並依賴 SwiftUI 預設 intrinsic size。DEBUG 版又把 `TestingActionMarker` 的 `NSButton` 放進可見按鈕背景。實際畫面可見「Reset」文字重疊、按鈕寬度與水平位置不一致，底部狀態文字也被 marker 邊框干擾；即使沒有執行定位或 Reset，初始布局就可能失真。這是既有操作介面的視覺 regression，會降低按鈕可辨識性與可點擊性。

## Proposed Solution

1. 在地圖側欄建立小型、明確的控制布局規則：單列主要操作填滿可用寬度並靠左對齊；同一列的成對次要操作使用一致間距；各功能群組維持固定垂直節奏，不以按鈕標題長度決定跨群組位置。
2. 將「到 Mac 位置」、`Reset`、搜尋、預覽端點、路線與 iPhone 定位區的所有可見按鈕逐一套用相同規則，保留 destructive role、disabled 狀態、confirmation 與既有 action 語義。
3. 調整 DEBUG hosting-view 測試 seam，使 `TestingActionMarker` 使用可辨識且不可接受 first responder 的專用 `NSButton` subclass，保持不可見、零布局影響，且仍能由既有 accessibility identifier 驗證 Reset 確認順序及狀態。
4. 新增同一個 rendered hierarchy 的布局 regression 測試，驗證 connected／disconnected、Reset busy／failure 與 route running／paused 等代表狀態下：可見按鈕不重疊、frame 位於側欄範圍、按鈕不覆蓋狀態文字區域、單列按鈕對齊一致，測試 marker 沒有可見尺寸、邊框或鍵盤 focus。

## Non-Goals

- 不改變「到 Mac 位置」、搜尋、清除、A/B、路線、定位、暫停、繼續、停止模擬或 `Reset` 的業務行為。
- 不重設側欄寬度、不改變地圖區比例，也不進行整體視覺風格重做。
- 不新增自訂 design system、第三方 UI dependency 或通用按鈕框架。
- 不改變 DEBUG seam 所覆蓋的 Reset 必須先確認再執行之安全邊界。

## Alternatives Considered

- 只移動「到 Mac 位置」與 `Reset`：無法處理既有按鈕依標題長度各自決定位置的根因，也不能防止狀態切換後再次跑版。
- 只隱藏 `TestingActionMarker`：可消除畫面重疊的一部分，但 production 與 DEBUG 仍缺少一致的按鈕對齊 contract。
- 建立全 App 的自訂 ButtonStyle：本次只有單一側欄需要修正，會擴大影響範圍與維護成本。

## Capabilities

### New Capabilities

- (none)

### Modified Capabilities

- `location-simulation`：新增地圖控制欄所有可見按鈕的穩定布局、狀態切換不跑版，以及 DEBUG 測試 seam 不影響可見布局的要求。

## Impact

- Affected specs:
  - `openspec/specs/location-simulation/spec.md`
- Affected code:
  - New:
    - (none)
  - Modified:
    - `iPhoneLocationMove/Features/Map/LocationMapView.swift`
    - `iPhoneLocationMoveTests/ContentViewTests.swift`
  - Removed:
    - (none)
