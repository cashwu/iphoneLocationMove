# Cash Propose Review — Round 2

## Reviewer Findings

### Critical

無。

### Warning

1. `severity`: Warning
   - `confidence`: 100
   - `layer`: design
   - `location`: `openspec/changes/add-package-app-script/design.md`「Decision 3」
   - `summary`: privileged trust gate 仍讀取 repository source `HelperInfo.plist`，未驗證 built embedded helper 實際攜帶的 `SMAuthorizedClients` requirement。
   - `recommendation`: 從 embedded helper 的 `__TEXT,__info_plist` 擷取並驗證 `SMAuthorizedClients`，加入 source／embedded metadata mismatch case。
   - reviewer source: Reviewer V — Verification
   - `disposition`: unresolved-prior

### Suggestion

無。

## Rating

- post-filter cumulative blocking Critical count: 0
- post-filter cumulative blocking Warning count: 1
- non-blocking triaged finding count: 0
- `critical_gap`: false
- `round_type`: micro

Reviewer V 明確確認 Round 1 的版本 consumer 與 deterministic test coverage members 已 resolved；privileged trust member 仍因 metadata oracle 指向 source plist 而 unresolved。該 member 保留在 cumulative blocking set，完成修正後必須再由後續 reviewer 驗證，因此本輪為 `next_round`。

## Fix Actions

- verified resolution removal：Round 1「`--version` 沒有 App metadata consumer」已由 Round 1 對 `proposal.md`、`design.md`、delta spec、`tasks.md` 的版本修正解決，Reviewer V 在本輪以 App `CFBundleShortVersionString` consumer、預設 build setting、built metadata oracle 與 structured scope 為證確認 resolved。
- verified resolution removal：Round 1「deterministic tests coverage 不完整」已由 Round 1 對 `design.md`、delta spec、`tasks.md` 的 fixture coverage 修正解決，Reviewer V 在本輪以 short aliases、非 root cwd、含空白路徑與 sentinel fail-before-clean 為證確認 resolved。
- 修改 `openspec/changes/add-package-app-script/design.md`：把 helper requirement oracle 改為從 built embedded helper 的 `__TEXT,__info_plist` 以 `otool`／`xxd` 擷取，並明定 metadata extraction 與 temporary verification cleanup。
- 修改 `openspec/changes/add-package-app-script/specs/macos-build-packaging/spec.md`：要求驗證 built helper 實際 metadata，新增 source／embedded metadata mismatch scenario。
- 修改 `openspec/changes/add-package-app-script/tasks.md`：補上 `otool`／`xxd` shims、metadata extraction failure、source／embedded mismatch tests 與實際 built artifact acceptance。
- 修正後執行 fix propagation grep，確認 `__TEXT,__info_plist`、`otool`、`xxd`、built embedded helper、source／embedded mismatch 與 `SMAuthorizedClients` 在 artifacts 間一致。
- 修正後重新執行機械式自檢；annotation、identifier、title identity 與 open signal checks 均無失敗。
- 修正後重新執行 `/Users/cash/Github/iphoneLocationMove/.cash-skills/bin/cash validate "add-package-app-script"`，結果為 `Validation passed.`。

## Decision

next_round
