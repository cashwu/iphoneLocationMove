## Summary

在步行路線模擬期間，於地圖顯示一個可與 A、B 端點及 Mac 目前位置清楚區分的 iPhone 位置 marker，並只依 iPhone 已成功確認的 route coordinate 更新，讓使用者直接看出模擬位置目前走到哪裡。

## Motivation

目前地圖會顯示步行路線、A／B 端點與 Mac 目前位置，但 route 每秒成功更新 iPhone 位置時沒有對應的視覺標記。使用者只能從距離與時間文字推測進度，無法確認 iPhone 模擬位置是否仍沿路移動，也容易把 Mac 位置誤認為 iPhone 位置。

現有 route session 已在 device mutation 成功後保存 confirmed coordinate：route state透過`RouteSimulationSnapshot.confirmedCoordinate`公開，stopping state則由同一`RouteSession.confirmedCoordinate`保留。因此這項Feature應直接呈現同一份route confirmed truth，不建立預測座標、第二套route progress或新的recovery state。

## Proposed Solution

- 讓地圖直接觀察目前`SimulationStore`，將route confirmed truth映射為iPhone route marker：route state讀取`RouteSimulationSnapshot.confirmedCoordinate`，stopping state讀取同一`RouteSession.confirmedCoordinate`。
- marker 使用與 A、B、preview、Mac 目前位置不同的圖示、色彩與標題，明確表示「iPhone 模擬位置」。
- marker 只在 coordinate 已由 iPhone mutation 成功確認後移動；mutation pending 或 transport recovery pending 時停留在最後確認位置，不提前顯示預測進度。
- route 暫停時保留 marker；單程完成時停在終點；position仍可信時，stop／clear pending或clear failure保留最後確認位置；clear成功、session replacement、USB disconnect或position-unknown interruption後移除 marker，且後續進入stopping也不得重新顯示。
- 以穩定 annotation identity 更新 coordinate，避免每秒移除重建造成閃爍；marker-only更新同時保留既有route overlay identity，不得觸發 route fit、Mac initial center 或其他 programmatic camera effect，也不得搶走使用者手動 camera ownership。
- 增加 deterministic tests，驗證 marker 的顯示、移動、保留與移除條件，以及同一 rendered hierarchy 在 publisher 更新後確實刷新 marker，但不重播既有 camera effect。

## Non-Goals

- 不新增 predicted／pending route marker，也不改變 route 插值、速度、更新 cadence、confirmed progress 或 recovery 行為。
- 不讓地圖每秒自動跟隨或重新置中 marker，不新增「跟隨 iPhone」模式。
- 不修改 A／B、preview 或 Mac 目前位置的資料來源與 camera contract。
- 不新增 route history、軌跡尾巴、方向箭頭或自訂 marker 外觀設定。
- 不在 position unknown 時保留一個看似可信的 iPhone 位置。

## Alternatives Considered

- **只顯示距離與 ETA**：既有文字無法讓使用者確認目前位置是否沿 route 更新，未解決地圖缺少即時回饋的問題。
- **顯示下一個 pending coordinate**：會把尚未被 iPhone 確認的位置呈現為真實狀態，違反既有 confirmed progress semantics。
- **每次更新自動置中 marker**：會干擾使用者查看其他地區，並可能重播既有 route camera effect。
- **每秒移除並重建全部 annotations**：實作簡單但容易閃爍，也增加 callout 與 annotation identity 不穩定的風險。

## Capabilities

### New Capabilities

- (none)

### Modified Capabilities

- `location-simulation`：在 route simulation 中顯示由 `confirmedCoordinate` 驅動的 iPhone marker，並定義 pause、complete、interruption、clear 與 camera ownership 下的可觀察行為。

## Impact

- Affected specs:
  - `openspec/specs/location-simulation/spec.md`
- Affected code:
  - New:
    - (none)
  - Modified:
    - `iPhoneLocationMove/Features/Map/LocationMapView.swift`
    - `iPhoneLocationMove/Features/Simulation/SimulationStore.swift`
    - `iPhoneLocationMoveTests/LocationMapModelTests.swift`
    - `iPhoneLocationMoveTests/ContentViewTests.swift`
    - `iPhoneLocationMoveTests/SimulationStoreTests.swift`
  - Removed:
    - (none)
