# Cash Apply Review — Round 2

## Reviewer Findings

### Critical

None.

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `openspec/changes/add-macos-location-simulator/design.md` Implementation Contract §4、`iPhoneLocationMove/Device/PymobiledeviceAdapter.swift:771-777`；`summary`: 一般 `prepareSession` 已在 `startTunnel` 前 fail closed執行 `reconcileTunnels()`，但 transport recovery仍在停止舊 lease後直接呼叫 `startTunnel`，使 prior startup reconcile缺口未完整傳播至所有 production start call sites；`recommendation`: 在 recovery start前加入 `reconcileTunnels()`，並驗證 ordering及 failure不會呼叫 start／DVT；`disposition`: unresolved-prior；reviewer source：Reviewer A — Adherence。

2. `severity`: Warning；`confidence`: 99；`layer`: design；`location`: `iPhoneLocationMoveTunnelHelper/main.swift:1222-1224`、`iPhoneLocationMoveTests/TunnelHelperContractTests.swift` active idempotency case；`summary`: active same-key start直接回傳保存的 `.running` snapshot，沒有確認 process仍存活；pending ownership refactor移除了舊有的 `isRunning` guard，因此 process自行退出且尚未經 `status`移除時會回傳死亡 lease；`recommendation`: 在 condition lock外確認 active process狀態，退出時只移除同一 lease identity並回傳 typed `processExited`，補 exited-before-retry測試；`disposition`: fix-introduced；`introduced_by`: apply-r1 endpoint ownership修復後的 `PendingTunnelStart`／`NSCondition` refactor，具體 change-diff位於 `iPhoneLocationMoveTunnelHelper/main.swift:1222-1224`；reviewer source：Reviewer B — Quality。

3. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `iPhoneLocationMove/App/iPhoneLocationMoveApp.swift:164-178,206-218`、`iPhoneLocationMoveTunnelHelper/Acceptance/cases.json`；`summary`: `endpoint-timeout`與`runtime-seal-tamper`捕捉任何 error都回傳 `passed: true`，可能把 authorization、XPC或process early-exit誤判為目標負向案例；`cases.json`另把 endpoint timeout預期值寫成 `tunnel-failure`，與 production evidence的 `timeout`不一致；`recommendation`: 依 case精確驗證 typed error，非預期錯誤回 `passed: false`，同步 manifest與 oracle tests；`disposition`: fix-introduced；`introduced_by`: apply-r1 production acceptance缺口修復新增的 fixed-case runner與 `cases.json`；reviewer source：Reviewer A — Adherence、Reviewer B — Quality。

4. `severity`: Warning；`confidence`: 88；`layer`: design；`location`: `iPhoneLocationMoveTunnelHelper/main.swift:1112-1139,1188-1192,1767-1781`；`summary`: helper自身若在 active tunnel期間 crash，launchd重啟後的新 manager沒有舊 child的 process-local ownership，可能留下 root orphan；目前 acceptance只驗證 App termination與XPC invalidation；`recommendation`: 由後續 change評估 process group或 root-owned ownership record，加入 helper kill／restart後 reconcile acceptance；`disposition`: new；`introduced_by`: 本 change的長時間 root child與 process-local lease dictionaries；reviewer source：Reviewer B — Quality。

### Suggestion

None.

## Rating

- post-filter cumulative blocking Critical: 0
- post-filter cumulative blocking Warning: 3
- non-blocking triaged finding: 1
- `critical_gap`: false
- `round_type`: full
- 理由：seeded cumulative set中四個 prior members已由兩位 reviewer確認 resolved；startup reconcile member因 recovery call site仍漏掉而維持 blocking。active stale lease與negative runner oracle為 prior fixes引入的兩項 blocking Warning。helper自身crash ownership是 `new` finding，依 seeded規則只做 non-blocking triage。三項 blocking findings均已完成修正，須由下一輪 micro reviewer驗證後才能移出 cumulative set。

## Fix Actions

- 修改 `iPhoneLocationMove/Device/PymobiledeviceAdapter.swift`、`iPhoneLocationMoveTests/PymobiledeviceAdapterTests.swift`：transport recovery在 `startTunnel` 前 fail closed執行 `reconcileTunnels()`，新增 failure不呼叫 start／DVT測試，並同步既有 recovery ordering assertions。
- 修改 `iPhoneLocationMoveTunnelHelper/main.swift`、`iPhoneLocationMoveTests/TunnelHelperContractTests.swift`：active same-key fast path在 condition lock外檢查 process，死亡時只移除相同 lease identity並回傳 `processExited`；新增 exited-before-retry且不 relaunch測試。
- 修改 `iPhoneLocationMove/App/iPhoneLocationMoveApp.swift`、`iPhoneLocationMoveTests/AppLifecycleTests.swift`、`iPhoneLocationMoveTunnelHelper/Acceptance/cases.json`：`endpoint-timeout`只接受 `.timeout`，`runtime-seal-tamper`只接受含 runtime／seal detail的 `.tunnelFailure`，其他錯誤回 `passed: false`；同步 endpoint expected code與 oracle tests。
- Non-blocking triage：helper自身crash後的 child ownership屬本輪 `new` Warning，不加入 cumulative blocking set；review loop結束後依 signals write step建立或更新對應 issue class。
- Seed verified-resolution removal：`production privileged adversarial acceptance不足`由 Reviewer A與Reviewer B確認 resolved，依 production XPC matrix與最終 uninstall evidence移出 cumulative set。
- Seed verified-resolution removal：`endpoint等待期間root process未受可取消ownership保護`由 Reviewer A與Reviewer B確認 resolved，依 `PendingTunnelStart`／deadline／invalidation tests與 production timeout evidence移出 cumulative set。
- Seed verified-resolution removal：`caller trust未達audit-token binding宣稱`由 Reviewer A與Reviewer B確認 resolved，依修訂後公開API contract、connection-specific identity與 production caller rejection evidence移出 cumulative set。
- Seed verified-resolution removal：`generated runtime缺完整digest驗證`由 Reviewer A與Reviewer B確認 resolved，依完整 generated-file seal與 production tamper matrix移出 cumulative set。
- `startup缺少fail-closed reconcile`因 Reviewer A判定 recovery call site unresolved而保留；Reviewer B的 resolved verdict不覆蓋此 unresolved verdict。
- 驗證：focused tests通過；完整 `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS'`通過；Release build通過；`git diff --check`通過。
- Post-fix mechanical self-check：delta annotation counts平衡；核心 identifiers與所有 `boundary.startTunnel`／`reconcileTunnels` call sites已 cross-grep；`cases.json`與 runner error oracle一致；open signals沒有 `check`欄位。
- Cash touched state已記錄上述七個 implementation／test／acceptance files。

## Decision

next_round
