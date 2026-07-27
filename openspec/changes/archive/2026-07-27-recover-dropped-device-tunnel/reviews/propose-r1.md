# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

1. `severity`: Critical；`confidence`: 100；`layer`: design；`location`: `proposal.md`「Modified Capabilities」與 `specs/device-tunnel-recovery/spec.md`「每筆 mutation 最多執行一次 transport recovery」；`summary`: recovery success 維持 route running，與既有 `location-simulation` 對 helper exit／tunnel death 立即進入 `interrupted(positionUnknown)` 的 normative contract 互斥，但 proposal 未宣告 modified capability，也沒有對應 delta；`recommendation`: 將 `location-simulation` 列為 Modified capability，並以逐字相符的 requirement title 修改既有 interruption contract，限定 eligible recovery success 的例外與 terminal failure 行為；reviewer source: Reviewer B。
2. `severity`: Critical；`confidence`: 100；`layer`: design；`location`: `design.md`「單次 transport recovery transaction」與 `tasks.md` 1.3、3.2；`summary`: recovery 只在 transaction 入口檢查 logical session/current device，未定義每個 external await 前後的 generation/device gate；actor reentrancy 可能讓 USB disconnect、quit 或 reconnect 插入後，舊 recovery 仍建立 transport或重播舊座標；`recommendation`: 對 status、stop、start tunnel、start DVT、replay 與 commit 前後加入 captured logical generation/device validation，失效時清理本 transaction 新資源，並增加 disconnect／quit／reconnect 競態測試；reviewer source: Reviewer B。

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `design.md`「tunnel status 回傳 bounded process diagnostics」與 `tasks.md` 1.1、2.1、4.3；`summary`: privacy contract 要求 diagnostic 不記錄 RSD endpoint／座標，但目前設計依賴既有 logger sanitize；實際 sanitizer 只截長與移除換行，不會 redact endpoint或座標；`recommendation`: 定義寫入 diagnostic metadata 前的結構化 redaction／安全欄位，並以含 IPv6 endpoint、port與座標的 injected detail 建立 deterministic assertion；reviewer source: Reviewer B。

### Suggestion

None.

## Rating

- Post-filter cumulative blocking Critical count: 2
- Post-filter cumulative blocking Warning count: 1
- Non-blocking triaged finding count: 0
- `critical_gap`: true
- `round_type`: full

Reviewer B 完成並提供三項 confidence 100 的 design findings；Reviewer A 原始呼叫與唯一允許的 fresh retry 均未回傳，因此 full round 缺少必要角色，不能形成有效的完整品質判定。

## Fix Actions

- Pre-round mechanical self-check 修正 `tasks.md` 4.3 的 diagnostic event 順序，使其與 `design.md` 一致；修改檔案：`openspec/changes/recover-dropped-device-tunnel/tasks.md`。
- Reviewer A 原始呼叫無回應後已依規則 fresh retry；retry 仍在多次等待與立即回傳要求後無回應，構成同一 reviewer role 連續失敗。
- 因 sub-agent failure abort，未進入 finding fix phase；Reviewer B findings 保留於本 round，供後續 workflow 處理。

## Decision

aborted

Reviewer A 角色連續兩次未回傳；依 reviewer failure handling，中止本次 cash workflow，不將缺少必要 reviewer 的 round 標記為通過。
