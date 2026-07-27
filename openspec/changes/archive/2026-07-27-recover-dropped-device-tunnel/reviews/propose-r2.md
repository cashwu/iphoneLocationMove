# Cash Propose Review — Round 2

## Reviewer Findings

### Critical

1. `severity`: Critical；`confidence`: 100；`layer`: design；`disposition`: unresolved-prior；`location`: `design.md`「將 logical device session 與可替換 transport identity 分離」、「單次 transport recovery transaction」；`summary`: `DeviceTransportGeneration` 同時被當作 tunnel／DVT pair identity與recovery cancellation token；switch／quit若在clear前遞增，正確old transport的clear reply會被判為stale；`recommendation`: 使用獨立recovery ownership epoch取消舊recovery，保留old transport identity完成序列化clear，clear terminal後才替換transport generation；reviewer source: Reviewer B。

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`disposition`: new；`location`: `proposal.md`「Proposed Solution」對照`design.md`「診斷事件與 acceptance」與`tasks.md` 4.4；`summary`: proposal一度把實體iPhone強制中斷acceptance列為必然交付，但design／tasks允許環境不安全時用deterministic boundary test取代；`recommendation`: 將實機長時間acceptance設為必做、deterministic強制中斷設為必做，實體injection只在可安全執行時加做；reviewer source: Reviewer A。
2. `severity`: Warning；`confidence`: 100；`layer`: design；`disposition`: new；`location`: `specs/device-tunnel-recovery/spec.md`「stop cleanup recovery失敗」與`tasks.md` 1.3、1.4；`summary`: clear recovery terminal failure要求保留cleanup ownership與retry clear，但原tasks未直接區分set interruption與stop-clear failure的state assertions；`recommendation`: adapter tests明列clear rebuild／replay failure，SimulationStore tests驗證保持stopping／cleanup ownership、retry clear可用且不得回idle；reviewer source: Reviewer B。

### Suggestion

None.

## Rating

- Post-filter cumulative blocking Critical count: 1
- Post-filter cumulative blocking Warning count: 0
- Non-blocking triaged finding count: 2
- `critical_gap`: true
- `round_type`: full

Round 1 的capability conflict與diagnostic redaction經兩位reviewer確認resolved；actor reentrancy finding因Reviewer B判定identity機制仍互斥而保持blocking。兩項`new` Warning依rerun disposition規則列為non-blocking triage，但仍在本輪同步修正。

## Fix Actions

- Verified resolution removal：Round 1 capability conflict經Reviewer A與Reviewer B確認resolved；`proposal.md`宣告`location-simulation` Modified capability，`specs/location-simulation/spec.md`新增recoverable-pending precedence requirement。
- Verified resolution removal：Round 1 diagnostic redaction經Reviewer A與Reviewer B確認resolved；persistent log已改為allowlisted structured fields，並有含endpoint／座標fixture的negative assertion task。
- 修正blocking actor reentrancy finding：修改`design.md`、`tasks.md`與`specs/device-tunnel-recovery/spec.md`，新增獨立`RecoveryOwnershipEpoch`；switch／quit只先失效recovery epoch，再透過同一mutation queue對old device clear，clear terminal後才替換transport identity。
- Non-blocking triage與修正：實機acceptance scope finding標記為`new`；修改`proposal.md`，明確規定實機長時間acceptance必做、deterministic強制中斷必做、實體injection僅安全時加做。
- Non-blocking triage與修正：clear cleanup ownership test gap標記為`new`；修改`design.md`與`tasks.md`，明列adapter clear rebuild／replay failure及SimulationStore stopping／retry-clear assertions。
- Post-fix mechanical self-check：兩份delta spec的annotation配對正常；`RecoveryOwnershipEpoch`、`DeviceTransportGeneration`、old-device clear與acceptance wording已跨proposal／design／specs／tasks同步。
- Post-fix validation：`cash validate recover-dropped-device-tunnel`通過。

## Decision

next_round

blocking Critical已有明確fix，但依cumulative-set規則必須由下一輪fresh Reviewer V確認resolved後才能移出；兩項non-blocking findings亦已同步修正。
