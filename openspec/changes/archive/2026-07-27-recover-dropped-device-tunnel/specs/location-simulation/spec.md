## ADDED Requirements

### Requirement: 可恢復 transport closure 的中斷判定

系統 SHALL將structured `transport-closed`與terminal helper／tunnel failure分開處理。對符合`device-tunnel-recovery` contract的single-in-flight mutation，系統 SHALL在one-shot recovery terminal前將completion視為recoverable pending，MUST NOT提前發布running success或`interrupted`。active `set` recovery success後 SHALL沿用既有active session，recovery failure後 SHALL依既有裝置中斷contract進入`interrupted(positionUnknown)`；`clear` recovery failure則 SHALL保留stopping／cleanup ownership與retry clear，MUST NOT回到idle。`set` timeout、local DVT helper exit、tunnel status `exited`、non-transport backend failure及無法驗證ownership的completion MUST NOT套用此例外。

#### Scenario: structured transport closure recovery成功

- **GIVEN** active route或point session有一筆single-in-flight absolute mutation
- **WHEN** 該mutation回傳structured `transport-closed`，且one-shot recovery與同一mutation replay成功
- **THEN** 系統 SHALL保持原本的`SimulationSessionID`
- **AND** route或point session SHALL維持active
- **AND** confirmed mutation result SHALL只提交一次

#### Scenario: structured transport closure recovery失敗

- **GIVEN** active route或point session正在處理structured `transport-closed`
- **WHEN** ownership gate、transport rebuild或mutation replay失敗
- **THEN** 系統 SHALL立即停止producer並進入`interrupted(positionUnknown)`
- **AND** UI MUST NOT繼續顯示running或active
- **AND** 系統 SHALL提供對current device ownership的reconnect／clear或retry路徑

#### Scenario: clear recovery失敗

- **GIVEN** simulation正在執行clear且仍擁有可能殘留的裝置位置
- **WHEN** ownership gate、transport rebuild或clear replay失敗
- **THEN** 系統 SHALL保持stopping／cleanup ownership與retry clear
- **AND** UI MUST NOT顯示running、idle或已恢復真實定位

#### Scenario: terminal helper或tunnel failure

- **WHEN** active route或point session遇到`set` timeout、local DVT helper exit、tunnel status `exited`、non-transport backend failure或無法驗證ownership的completion
- **THEN** 系統 SHALL立即停止producer並進入`interrupted(positionUnknown)`
- **AND** 系統 MUST NOT自動建立replacement tunnel
