# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

無。

### Warning

1. `severity`: Warning
   - `confidence`: 100
   - `layer`: design
   - `location`: `proposal.md`「Proposed Solution」、`design.md`「Decision 3 / Implementation Contract 5」、`iPhoneLocationMove/Info.plist`
   - `summary`: `--version` 原本只傳入沒有 consumer 的 `MARKETING_VERSION`，無法改變 built App 的 `CFBundleShortVersionString`。
   - `recommendation`: 將 App version metadata 接到 `MARKETING_VERSION`，加入預設值、built artifact 驗證與對應 scope／tasks。
   - reviewer source: Reviewer A — Adherence、Reviewer B — Quality

2. `severity`: Warning
   - `confidence`: 100
   - `layer`: design
   - `location`: `design.md`「Decision 3 / Implementation Contract 6」、`tasks.md` 1.3、2.3、3.3
   - `summary`: 只驗證 App 與 helper 的 `TeamIdentifier` 相同，無法保證固定 identifier、Team `2LRM76M575` 與雙向 `SMJobBless` requirements。
   - `recommendation`: 驗證實際 signed identifiers、固定 Team 與 `SMPrivilegedExecutables`／`SMAuthorizedClients` requirements，並加入相同但錯誤 Team、identifier 與 requirement mismatch tests。
   - reviewer source: Reviewer B — Quality

3. `severity`: Warning
   - `confidence`: 100
   - `layer`: design
   - `location`: `design.md`「Decision 5 / Implementation Contract 1、3、9」、`tasks.md` 1.1–1.3
   - `summary`: deterministic tests 原本未明列非 root current directory、含空白 project path、marker fail-before-clean 與 `-h`／`-v` aliases。
   - `recommendation`: 將上述 public contract cases 加入 fixture 設計與 tasks，並以 sentinel build content 驗證 marker 失敗不會先清理。
   - reviewer source: Reviewer A — Adherence

### Suggestion

無。

## Rating

- post-filter cumulative blocking Critical count: 0
- post-filter cumulative blocking Warning count: 3
- non-blocking triaged finding count: 0
- `critical_gap`: false
- `round_type`: full

第一輪三筆高信心 Warning 都直接指出 design contract 或驗收 coverage 缺口，因此全部進入 cumulative blocking set。已完成修正，但依規則必須由後續 reviewer 驗證修正位置未再出現相同機制，故本輪為 `next_round`。

## Fix Actions

- 修改 `openspec/changes/add-package-app-script/proposal.md`：擴充版本 metadata 與 privileged trust gate 敘述，並把 `iPhoneLocationMove/Info.plist`、`iPhoneLocationMove/project.yml`、`iPhoneLocationMove.xcodeproj/project.pbxproj` 加入 structured scope。
- 修改 `openspec/changes/add-package-app-script/design.md`：定義 `MARKETING_VERSION` consumer／預設值／built metadata oracle，固定 App／helper identifiers 與 Team `2LRM76M575`，加入雙向 `SMJobBless` requirement gate，並補齊 PATH-shim coverage。
- 修改 `openspec/changes/add-package-app-script/specs/macos-build-packaging/spec.md`：新增 short aliases、版本 metadata、相同但錯誤 Team、fixed identity、雙向 requirement 與 path／marker test scenarios。
- 修改 `openspec/changes/add-package-app-script/tasks.md`：補上所有對應 TDD cases、version build settings delivery targets、固定 trust contract 驗證與實際工具鏈 acceptance。
- 修正後執行 fix propagation grep，確認 `MARKETING_VERSION`、`CFBundleShortVersionString`、`2LRM76M575`、`SMPrivilegedExecutables`、`SMAuthorizedClients`、short aliases 與含空白路徑在全部 artifacts 一致。
- 修正後重新執行機械式自檢；annotation、identifier、title identity 與 open signal checks 均無失敗。
- 修正後重新執行 `/Users/cash/Github/iphoneLocationMove/.cash-skills/bin/cash validate "add-package-app-script"`，結果為 `Validation passed.`。

## Decision

next_round
