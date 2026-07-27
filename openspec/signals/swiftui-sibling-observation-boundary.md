---
id: swiftui-sibling-observation-boundary
type: recurring-finding
status: open
occurrences: 2
first_seen: 2026-07-27
last_seen: 2026-07-27
links:
  - openspec/changes/show-mac-location-on-device-ready/reviews/propose-r1.md
  - openspec/changes/add-mac-recenter-and-workspace-reset/reviews/propose-r1.md
---
# SwiftUI sibling observation 未更新共同輸入

當 sibling view 各自依賴同一個 `ObservableObject` 時，只在其中一個 subtree 觀察 object 不會保證父層重算另一個 sibling 的輸入；共同 state 衍生應由直接觀察該 object 的共同 shell 擁有。

## Occurrences

- 2026-07-27 — `show-mac-location-on-device-ready` — `cash-propose` Round 1：ready generation 最初由未觀察 `DeviceSetupStore` 的 `ContentView` 衍生。
- 2026-07-27 — `add-mac-recenter-and-workspace-reset` — `cash-propose` Round 1：reset 需清空的 `message` 是 sibling `SimulationControls` 的 view-local `@State`，design 最初只上移 `roundTrip` 而漏掉它。
