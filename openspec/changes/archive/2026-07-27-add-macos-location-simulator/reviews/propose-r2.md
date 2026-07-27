# Cash Propose Review — Round 2

## Reviewer Findings

### Critical

1. `severity`: Critical；`confidence`: 100；`layer`: design；`disposition`: unresolved-prior；`location`: `design.md`「Privileged tunnel 最小化」與 Implementation Contract、`specs/ios-device-session/spec.md`、`tasks.md` 2.4／7.3；`summary`: offline payload 與外部 hash manifest 仍可一起替換，缺少 code signature／designated requirement／Team ID 與 signed-helper embedded manifest trust anchor；`recommendation`: 將 digest table 固定在 signed helper，從 audit token 驗證 caller code，並測試 payload＋manifest replacement 與 invalid signature fail closed；reviewer source：Reviewer V — Verification。

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`disposition`: unresolved-prior；`location`: `design.md` route update barrier、`specs/location-simulation/spec.md`「路線更新背壓與操作屏障」、`tasks.md` 4.2；`summary`: in-flight `set` 可能在 pause snapshot 後成功套用更遠座標，舊 completion 只被禁止更新 UI，未保證 iPhone 實際停在 snapshot；`recommendation`: 定義 `pausing` transaction、等待 in-flight、必要時 correction `set`，不確定則進入 `interrupted(positionUnknown)`；reviewer source：Reviewer V — Verification。
2. `severity`: Warning；`confidence`: 100；`layer`: design；`disposition`: unresolved-prior；`location`: `design.md` Implementation Contract privilege boundary；`summary`: Decision、spec 與 tasks 要求 `reconcile()`，Implementation Contract 卻只列 start／stop／status；`recommendation`: 同步 exact typed operation contract；reviewer source：Reviewer V — Verification。

### Suggestion

None.

## Rating

- post-filter cumulative blocking Critical: 1
- post-filter cumulative blocking Warning: 2
- non-blocking triaged finding: 0
- `critical_gap`: true
- `round_type`: micro
- 理由：Reviewer V 已驗證移除 W1–W4 與 W7–W11，但 C1、W5、W6 仍是 `unresolved-prior`；本輪完成精確修正後仍需 fresh verification 才能從 cumulative blocking set 移除，因此為 `next_round`。

## Fix Actions

- verified resolution removal：W1 completed transitions；Round 1 design fix 已由 Reviewer V 驗證。
- verified resolution removal：W2 device selection UI；Round 1 spec／tasks fix 已由 Reviewer V 驗證。
- verified resolution removal：W3 helper protocol docs／fixtures；Round 1 tasks fix 已由 Reviewer V 驗證。
- verified resolution removal：W4 one-second scheduler coverage；Round 1 spec／tasks fix 已由 Reviewer V 驗證。
- verified resolution removal：W7 transport failure state；Round 1 design／spec／tasks fix 已由 Reviewer V 驗證。
- verified resolution removal：W8 transactional device switch；Round 1 design／spec／tasks fix 已由 Reviewer V 驗證。
- verified resolution removal：W9 replacement first-mutation failure；Round 1 design／spec／tasks fix 已由 Reviewer V 驗證。
- verified resolution removal：W10 MapKit async generations；Round 1 design／spec／tasks fix 已由 Reviewer V 驗證。
- verified resolution removal：W11 real privileged acceptance；Round 1 design／tasks fix 已由 Reviewer V 驗證。
- 修改 `proposal.md`：把 privileged payload trust anchor 明確提升為 App code signature／designated requirement／Team ID 與 signed-helper embedded digest table。
- 修改 `design.md`：定義從 XPC audit token 驗證 caller code、不可外部替換的 embedded digest table、payload＋manifest replacement fail closed；加入 `pausing`／correction transaction；同步 exact `startTunnel(deviceID, idempotencyKey)`、`stopTunnel(leaseID)`、`status(leaseID)`、`reconcile()` Implementation Contract。
- 修改 `specs/ios-device-session/spec.md`：新增 caller signature trust anchor 與 payload＋manifest 同時替換 fail-closed scenario，並同步 exact XPC operations。
- 修改 `specs/location-simulation/spec.md`：要求 `pausing` 等待 in-flight，必要時 correction 回 snapshot，結果不確定則 `interrupted(positionUnknown)`。
- 修改 `tasks.md`：加入 code-signature／Team ID／embedded digest acceptance 與 fake-device final-coordinate pause transaction tests。
- 修正後機械自檢通過：annotation 均為 `0/0`、無 stray separator、18 個 requirements／67 個 scenarios／2 個 examples／24 個 tasks 的來源計數已重算、trust-anchor／pause／reconcile identifiers 跨 artifacts 一致、沒有 MODIFIED／REMOVED title identity 或 open signal check。
- 修正後 `cash validate add-macos-location-simulator` 通過。

## Decision

next_round
