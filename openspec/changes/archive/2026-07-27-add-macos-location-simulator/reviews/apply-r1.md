# Cash Apply Review — Round 1

## Reviewer Findings

### Critical

1. `severity`: Critical；`confidence`: 100；`layer`: design；`location`: `tasks.md` 7.3、`acceptance-results.md` task 7.3、`iPhoneLocationMoveTests/TunnelHelperContractTests.swift`、`iPhoneLocationMoveTests/TunnelXPCInterfaceTests.swift`；`summary`: task 7.3 被過早勾選，真實環境只證明合法 caller 的正向 tunnel、安裝 metadata 與 cleanup，多數 adversarial cases 仍只由 user-space fake harness 驗證，未達 task 指定的 production privileged boundary acceptance；`recommendation`: 恢復 7.3 未完成，補跑 production helper 的 invalid caller／signature／tamper／idempotency／lost reply／crash cleanup acceptance，或先透過 `$cash-ingest` 明確拆分 acceptance contract；`introduced_by`: 本輪新增 `acceptance-results.md` 並將 task 7.3 勾為完成；reviewer source：Reviewer A — Adherence、Reviewer B — Quality。

2. `severity`: Critical；`confidence`: 100；`layer`: design；`location`: `design.md` privilege／verification contract、`ios-device-session` spec「App 啟動時 reconcile」、`iPhoneLocationMove/Device/PymobiledeviceAdapter.swift` startup／teardown paths；`summary`: production startup／`prepareSession` path 沒有呼叫 `boundary.reconcileTunnels()`，唯一 production call site 位於 quit teardown，違反新 signed XPC session 應先回收 stale lease 的 scenario；`recommendation`: 在 start 前加入 fail-closed reconcile ordering 與 typed setup failure，並補 production-boundary ordering tests；reviewer source：Reviewer A — Adherence。

3. `severity`: Critical；`confidence`: 98；`layer`: design；`location`: `iPhoneLocationMoveTunnelHelper/main.swift` process endpoint read、`TunnelLeaseManager.startTunnel` 與 connection invalidation paths；`summary`: `readEndpointLine()` 沒有 deadline，`startTunnel()` 持有 manager lock 等待 newline，且 process 尚未登記 lease；若 process 存活但不輸出 endpoint，App crash／XPC invalidation 無法取得 lock或回收該 root process；`recommendation`: 設計有限 endpoint deadline 與 starting ownership，使 timeout、connection invalidation及caller death都能停止尚未產生 endpoint 的 process，並以 production-like hanging-process test驗證；`introduced_by`: 原始實作不在本輪 diff，但本輪 task 7.3 completion與acceptance結果把未覆蓋路徑宣稱完成；reviewer source：Reviewer B — Quality。

### Warning

1. `severity`: Warning；`confidence`: 98；`layer`: design；`location`: `design.md` audit-token claim、`iPhoneLocationMoveTunnelHelper/main.swift` caller identity／Security verification；`summary`: artifacts 宣稱從 XPC audit token解析caller code並驗證所有audit identity，但實作只從connection擷取PID／EUID／audit session，再以PID建立`SecCode`；EUID與audit session沒有進入Security trust decision；`recommendation`: 使用connection-bound audit token完成Security驗證，或透過`$cash-ingest`修訂安全contract並補production-boundary test；reviewer source：Reviewer A — Adherence。

2. `severity`: Warning；`confidence`: 97；`layer`: design；`location`: `iPhoneLocationMoveTunnelHelper/main.swift` generated runtime validation、`TunnelHelperContractTests.swift` wheelhouse test、`implementation-notes.md` offline target install deviation；`summary`: embedded digest只固定wheelhouse與manifest，`pip --target`產生的runtime tree只驗owner、writable與symlink，允許未列入trust anchor的額外generated runtime內容，不符合每次start前驗證runtime digest的contract；`recommendation`: 在packaging階段產生並嵌入完整runtime digest tree，啟動前拒絕額外檔案與digest mismatch；若保留目前機制，必須透過`$cash-ingest`修改trust contract；`introduced_by`: `implementation-notes.md`「privileged runtime 改用離線 target 安裝」deviation；reviewer source：Reviewer B — Quality。

### Suggestion

None.

## Rating

- post-filter cumulative blocking Critical: 3
- post-filter cumulative blocking Warning: 2
- non-blocking triaged finding: 0
- `critical_gap`: true
- `round_type`: full
- 理由：第一輪五項 Critical／Warning 全部進入 cumulative blocking set。endpoint hang 的修正需要 design 未定義的 starting ownership state 與同步／取消機制；generated runtime digest亦需要調整 packaging trust design，因此觸發 cash-apply Fix-loop design circuit breaker，本輪不得直接實作並續跑。

## Fix Actions

- Pre-round mechanical self-check：修改 `design.md` 與 `tasks.md`，將已記錄的 contract-preserving helper安裝deviation由過時的`SMAppService`同步為實際`SMJobBless`機制；`cash validate add-macos-location-simulator`通過。
- 修改 `tasks.md`：恢復task 7.3與7.6為未完成；task 7.4依使用者明確sign-off保持完成。
- 修改 `acceptance-results.md`：保留已完成的真實安裝、隔離suite與cleanup證據，但明記7.3仍缺production adversarial acceptance與四項contract gaps，7.6須等待這些缺口解決。
- `needs-design`：endpoint hang需要 design 未定義的 starting process ownership state、有限deadline及跨XPC invalidation的同步／取消機制，符合 circuit breaker 片語 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。
- `needs-design`：generated runtime digest需要決定完整runtime packaging／trust-anchor模型；保留本機`pip --target`會改變既有runtime integrity contract，需由`$cash-ingest`處理。
- Abort triage bucket 1 — remains this change's obligation：production privileged adversarial acceptance不足。
- Abort triage bucket 1 — remains this change's obligation：startup缺少fail-closed `reconcile()`。
- Abort triage bucket 1 — remains this change's obligation：endpoint等待期間root process未受可取消ownership保護。
- Abort triage bucket 1 — remains this change's obligation：caller trust未達audit-token binding宣稱。
- Abort triage bucket 1 — remains this change's obligation：generated runtime缺完整embedded digest驗證。
- Abort triage bucket 2：無。
- Abort triage bucket 3：無；本輪沒有接受風險。

## Decision

aborted
