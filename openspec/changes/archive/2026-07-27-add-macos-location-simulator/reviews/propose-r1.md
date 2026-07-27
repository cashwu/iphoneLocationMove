# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

1. `severity`: Critical；`confidence`: 90；`layer`: design；`location`: `design.md`「Privileged tunnel 最小化」、`tasks.md` 2.4；`summary`: root-owned tunnel runtime 未定義 payload provenance、完整性驗證及 symlink／TOCTOU 防護，可能形成 root code-execution 供應鏈邊界；`recommendation`: 使用可信 offline payload、hash 驗證、原子安裝並禁止 root 執行網路或 user-writable code；reviewer source：Reviewer B — Quality。

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `design.md`「RouteSession state machine」；`summary`: `completed` 缺少至 `stopping`、`interrupted` 與 replacement 的轉移；`recommendation`: 補齊 completed active-session transitions；reviewer source：Reviewer A — Adherence。
2. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `specs/ios-device-session/spec.md`「USB 裝置偵測與選擇」、`tasks.md`；`summary`: 多裝置選擇、裝置名稱與 iOS 版本 UI 沒有 backing task；`recommendation`: 新增 device-selection UI 與測試；reviewer source：Reviewer A — Adherence。
3. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `design.md` Implementation Contract、`tasks.md` 2.2；`summary`: JSON protocol 文件與 fixtures 沒有 delivery task；`recommendation`: 明列文件、fixtures 與使用它們的 tests；reviewer source：Reviewer A — Adherence。
4. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `specs/location-simulation/spec.md`「步行速度與距離進度」、`tasks.md`；`summary`: 約每秒 update scheduling 未被實作或驗證 task 覆蓋；`recommendation`: 加入 controllable-clock scheduler test；reviewer source：Reviewer A — Adherence。
5. `severity`: Warning；`confidence`: 95；`layer`: design；`location`: `design.md`「路線距離、tick 與速度」、`location-simulation` spec；`summary`: route update 沒有 backpressure、coalescing 或 pause barrier，慢 DVT completion 可能在暫停後套用舊座標；`recommendation`: 定義 single-in-flight、latest-only 與 epoch barrier；reviewer source：Reviewer B — Quality。
6. `severity`: Warning；`confidence`: 93；`layer`: design；`location`: `design.md` privileged tunnel／lifecycle、`ios-device-session` spec；`summary`: tunnel 缺少 idempotent lease、XPC invalidation、App crash、遺失 reply 與 ready-session quit 回收；`recommendation`: 以 caller／device／idempotency key 維護 lease 並 reconcile；reviewer source：Reviewer B — Quality。
7. `severity`: Warning；`confidence`: 91；`layer`: design；`location`: `design.md` route state machine／error handling、`tasks.md`；`summary`: mid-session set timeout、helper exit 或 tunnel death 沒有一致狀態轉移；`recommendation`: 停止 producer、進入 `interrupted(positionUnknown)` 並定義 recovery；reviewer source：Reviewer B — Quality。
8. `severity`: Warning；`confidence`: 90；`layer`: design；`location`: `ios-device-session` spec「USB 裝置偵測與選擇」、`design.md` reconnect；`summary`: ready／active 時切換 selected device 的 cleanup transaction 未定義；`recommendation`: 舊 UDID cleanup 完成後才 commit 新 selection；reviewer source：Reviewer B — Quality。
9. `severity`: Warning；`confidence`: 89；`layer`: design；`location`: `location-simulation` spec「模擬模式互斥與安全取代」、`design.md`；`summary`: replacement 第一個 mutation 失敗時狀態不明；`recommendation`: 保留 current ownership 並進入 `interrupted(positionUnknown)`；reviewer source：Reviewer B — Quality。
10. `severity`: Warning；`confidence`: 87；`layer`: design；`location`: `location-simulation` spec「地圖搜尋、選點與明確確認」「A/B 步行路線預覽」；`summary`: MapKit async search／directions response 未綁定 current query 與 A/B revision；`recommendation`: 加入 generation 與 endpoint snapshot；reviewer source：Reviewer B — Quality。
11. `severity`: Warning；`confidence`: 86；`layer`: design；`location`: `tasks.md` 2.4、7.3、`design.md` privilege contract；`summary`: unit tests 與既有 physical acceptance 無法驗證實際 privileged deployment boundary；`recommendation`: 增加需管理員核准的隔離 acceptance gate；reviewer source：Reviewer B — Quality。

### Suggestion

1. `severity`: Suggestion；`confidence`: 75；`layer`: design；`location`: `proposal.md`、`design.md`、`ios-device-session` spec；`summary`: iOS 17+ 範圍沒有明確阻擋較舊 iOS；`recommendation`: 加入 unsupported 狀態、提示與 test；reviewer source：Reviewer A — Adherence。
2. `severity`: Suggestion；`confidence`: 75；`layer`: design；`location`: `location-simulation` spec「A/B 步行路線預覽」、`design.md` risks；`summary`: MapKit transient failure 與確定 no-route 未區分；`recommendation`: 區分 no-route、cancel、transient 與 stale；reviewer source：Reviewer B — Quality。

## Rating

- post-filter cumulative blocking Critical: 1
- post-filter cumulative blocking Warning: 11
- non-blocking triaged finding: 2
- `critical_gap`: true
- `round_type`: full
- 理由：第一輪有一個 root execution Critical 與十一個 contract／coverage Warning；即使本輪已完成修正，仍須由 fresh Reviewer V 驗證 cumulative blocking set 後才能移除，因此本輪為 `next_round`。

## Fix Actions

- 修改 `proposal.md`：補上 route backpressure／epoch barrier、tunnel lease 與 offline integrity boundary，並明確排除 root 網路 `pip` 與 user-writable code。
- 修改 `design.md`：補齊 completed transitions、`interrupted(positionUnknown)`、single-in-flight latest-only policy、`RouteUpdateEpoch` barrier、offline hash-locked atomic privileged install、`TunnelLeaseID`／idempotency／owner-death reconcile、transactional device switch、iOS 17 support gate、MapKit request generations、transient outcome 與 ready-session quit cleanup。
- 修改 `specs/ios-device-session/spec.md`：加入 privileged-safe interpreter、iOS 17 以下阻擋、device switch transaction、runtime integrity、idempotent lease、owner death、reconcile、command barrier 與 ready-session quit scenarios。
- 修改 `specs/location-simulation/spec.md`：加入 stale search／directions、transient failure、約一秒 scheduling、single-in-flight coalescing、pause barrier、replacement failure 與 mid-session transport failure scenarios。
- 修改 `tasks.md`：補上 device-selection UI、protocol 文件／fixtures、scheduler／backpressure tests、runtime tamper／lease tests、transport／replacement／MapKit race tests，以及隔離 privileged-helper acceptance。
- 修正兩個非阻塞 Suggestion：明定 iOS 17 以下 unsupported，並區分 MapKit no-route 與 transient／cancel／stale。
- 修正後機械自檢通過：兩份 spec annotation 均為 `0/0`、無 stray separator、18 個 requirements／65 個 scenarios／2 個 examples／24 個 tasks 的來源計數已重算、跨 artifact identifiers 一致、沒有 MODIFIED／REMOVED title identity 或 open signal check。
- 修正後 `cash validate add-macos-location-simulator` 通過。

## Decision

next_round
