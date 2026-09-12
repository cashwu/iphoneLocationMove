---
name: cash-ingest
description: "Update an existing Cash change from external context. Use when a plan or conversation decision changes an existing change's requirements."
argument-hint: "[change-name|plan-file]"
license: MIT
metadata:
  author: cash
  version: "1.0"
---

## Project-local Cash CLI bootstrap

執行任何 Cash artifact command 前，MUST 先從目前目錄解析並驗證 Git root，再使用該 root 下的 absolute launcher；不得依賴 PATH 或外部 runtime：

```shell
cash_root="$(git rev-parse --show-toplevel)" || exit 1
cash_cli="$cash_root/.cash-skills/bin/cash"
test -x "$cash_cli" || exit 1
```

同一段 workflow 後續每個 artifact command MUST 使用 `"$cash_cli"`。

Update an existing Cash change — from a plan file or conversation context.

This tool resolves plan file references as ordinary paths relative to the current working directory or repository root, and uses conversation context when no plan file is available.

**Prerequisites**: The project-local launcher initialized above is required. If root resolution, launcher validation, or a Cash command fails, report the exact error and STOP.

**Input**: Optionally specify an existing change name, or a plan file path or name. An existing change name selects the update target and uses conversation context as the requirement source.

- `$cash-ingest agile-discovering-rocket.md`
- `$cash-ingest agile-discovering-rocket`
- `$cash-ingest` (use conversation context or auto-detect plan file)

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

**Steps**

1. **Locate the requirement source**

   First, when an argument is provided, run `"$cash_cli" list --json` and `"$cash_cli" list --parked --json`. If it exactly matches an active or parked change name, retain that explicit target and use conversation context, then go to Step 3. This change-name match takes precedence over plan-file resolution below; an explicit path such as `./update-plan.md` selects a plan instead. If the context lacks the requested update, ask for that information; do not interpret the selected change as a missing plan file.

   a. **Argument provided** → treat as a plan file reference, resolve it relative to the current working directory or repository root, and append `.md` if needed
   - If the file exists → use it as the plan file source, proceed to Step 2
   - If the file does NOT exist → report the error and **stop**

   b. **No argument, plan file detectable**:
   - Check conversation context for a plan file path (plan mode system messages include paths like `<name>.md`); resolve it relative to the current working directory or repository root
   - If found and the file exists → use the **AskUserQuestion tool** to ask:
     - Option 1: 使用計畫檔
     - Option 2: 使用對話內容
   - If the user picks plan file → proceed to Step 2
   - If the user picks conversation context → skip Step 2, go to Step 3

   c. **No argument, no plan file detectable**:
   - Check the current working directory and repository root for recent plan files
   - If recent files exist → list 5 most recent with the **AskUserQuestion tool**, include "使用對話內容" as an additional option
   - If the user picks a file → proceed to Step 2
   - If the user picks conversation context → skip Step 2, go to Step 3

   d. **Conversation context fallback** (no plan files found at all):
   - 使用對話內容 to update artifacts
   - If conversation context is insufficient, use the **AskUserQuestion tool** to get more details
   - Warn: "找不到計畫檔，使用對話內容。"

2. **Parse the plan structure** (skip if using conversation context)

   Claude Code plan files typically contain:
   - **Title** (`# ...`) — the high-level goal
   - **Context** section — background, motivation, current state
   - **Stages/Steps** — numbered implementation stages with goals and file lists
   - **Files involved** — list of files to modify/create
   - **Verification** section — how to test the changes

   Extract:
   - `plan_title`: from the H1 heading
   - `plan_context`: from the Context section
   - `plan_stages`: each numbered stage with its goal and file list
   - `plan_files`: all file paths mentioned
   - `plan_verification`: verification steps

   If the plan content is too brief to fill the required artifact sections, use the **AskUserQuestion tool** to get the missing details rather than inventing content.

3. **Check for active changes** (REQUIRED — ingest only updates existing changes)

   ```bash
   "$cash_cli" list --json
   ```

   Also check for parked changes:

   ```bash
   "$cash_cli" list --parked --json
   ```

   Parse both JSON outputs to get the full list of changes (active + parked). Parked changes should be annotated with "(parked)" in any selection list.
   - If Step 1 retained an explicit target → use that target without asking the user to select again; Step 4's parked handling still applies
   - Otherwise, if one change exists (active or parked) → use the **AskUserQuestion tool** to confirm updating it
   - Otherwise, if multiple changes exist → use the **AskUserQuestion tool** to let user pick which one to update
   - If no changes at all (neither active nor parked) → tell the user: "No active change found. Use `$cash-propose` first to create one." and **stop**

4. **Select the change**

   After selecting the change, check if it is parked:

   ```bash
   "$cash_cli" list --parked --json
   ```

   If the selected change appears in the `parked` array:
   - Inform the user that this change is currently parked（暫存）
   - Use **AskUserQuestion tool** to ask: continue (unpark) or cancel
   - If continue: run `"$cash_cli" unpark "<name>"` then proceed
   - If cancel: stop the workflow

   Read existing artifacts for context before updating.

5. **Update artifacts**

   For each artifact, get instructions first:

   ```bash
   "$cash_cli" instructions <artifact-id> --change "<name>" --json
   ```

   Use the `template` from instructions as the output structure. Apply `context` and `rules` as constraints but do NOT copy them into the file.

   The instructions JSON includes `locale` — the language to write artifacts in. If present, you MUST write the artifact content in that language. For spec files (specs/\*/\*.md), the spec-file language policy takes precedence over `locale`: Traditional Chinese prose with English structural keywords (`### Requirement:`, `#### Scenario:`, GIVEN/WHEN/THEN/AND) and English normative verbs (SHALL / MUST and their NOT forms); every MODIFIED/REMOVED requirement title and every RENAMED FROM title MUST be copied byte-for-byte from the current master spec, because `"$cash_cli" archive` matches titles verbatim and fails closed with `requirement_identity_mismatch` when a title does not match.

   **Plan-to-Artifact Mapping** (when using a plan file):

   | Plan Section       | Artifact         | How to Map                                        |
   | ------------------ | ---------------- | ------------------------------------------------- |
   | Title              | Change name      | Convert to kebab-case                             |
   | Context            | proposal: Why    | Direct content transfer                           |
   | Stages overview    | proposal: What   | Summarize all stages                              |
   | Individual stages  | tasks.md groups  | One stage = one `##` heading, sub-items = `- [ ]` |
   | File paths         | proposal: Impact | Affected code list                                |
   | Verification steps | tasks.md         | Final verification task group                     |

   **Context-to-Artifact Mapping** (when using conversation context):

   | Conversation Element | Artifact         | How to Map                         |
   | -------------------- | ---------------- | ---------------------------------- |
   | Goal / requirement   | proposal: Why    | Extract motivation from discussion |
   | Discussed approach   | proposal: What   | Summarize agreed approach          |
   | Mentioned files      | proposal: Impact | Affected code list                 |
   | Discussion phases    | tasks.md groups  | One topic = one `##` heading       |

   **When updating an existing change:**
   - Merge new context into the existing artifacts and preserve unrelated content. When the user explicitly changes a requirement, scope, or approach, update or remove the superseded proposal, design, delta spec, and incomplete task content consistently; do not leave contradictory instructions active.
   - Add new tasks from plan stages or conversation, **preserve completed `[x]` items** unchanged as historical evidence. If a new decision reverses completed work, add a new pending migration or reversal task instead of deleting, rewriting, or unchecking the completed task.
   - **Preserve existing `[P]` markers** on tasks that still qualify
   - Remove or replace incomplete content only when supported by an explicit decision in the requirement source. Without that decision, preserve the content and ask about the conflict. Record what was superseded, the decision, and the affected artifacts in the change's design decision history (or proposal when no design exists), and include it in the final summary.
   - Preserve existing review records, implementation notes, and touched task attribution. Before rewriting or removing a pending task, check any existing `.cash-skills/state/touched/<change-name>.json` entries: if its exact description is already a `task_desc`, preserve that task and report the attribution conflict rather than silently changing the description or deleting its tracking entry. Existing explicit recovery guidance for a missing historical task still applies.

   **Mutually exclusive task authoring modes**: Preserve the existing schema and `task_order`. In `document` mode only, keep existing qualifying `[P]` markers and add markers for new independent tasks with disjoint regions when `parallel_tasks: true`. In `dependency` mode, do not add `[P]` markers; preserve legacy markers as text and synchronize `[after: ...]` references when adding or cancelling pending work. Never rewrite completed descriptions or touched provenance; keep migration steps independently buildable and verifiable.

   After creating each artifact, re-check status:

   ```bash
   "$cash_cli" status --change "<name>" --json
   ```

   Continue until all `applyRequires` artifacts are complete. Show progress: "✓ Created <artifact-id>"

6. **Inline Self-Review** (before CLI analysis)

   After updating all artifacts, scan them manually. Fix issues inline, then proceed to the CLI analyzer.

   **Check 1: No Placeholders**

   These patterns are artifact failures — fix each one before proceeding:
   - "TBD", "TODO", "FIXME", "implement later", "details to follow"
   - Vague instructions: "Add appropriate error handling", "Handle edge cases", "Write tests for the above"
   - Delegation by reference: "Similar to Task N" without repeating specifics
   - Steps describing WHAT without HOW: "Implement the authentication flow" (what flow? what steps?)
   - Empty template sections left unfilled
   - Weasel quantities: "some", "various", "several" when a specific number or list is needed

   **Check 2: Internal Consistency**
   - Does every capability in the proposal have a corresponding spec?
   - Does the design reference only capabilities from the proposal?
   - Do tasks cover all design decisions, and nothing outside proposal scope?
   - Are file paths consistent across proposal Impact, design, and tasks?
   - If a requirement changed, were its scenarios updated to match?

   **Check 3: Scope Check**
   - More than 15 pending tasks → consider decomposing into multiple changes
   - Any single task would take more than 1 hour → split it
   - Touches more than 3 unrelated subsystems → consider splitting

   **Check 4: Ambiguity Check**
   - Are success/failure conditions testable and specific?
   - Are boundary conditions defined (empty input, max limits, error cases)?
   - Could "the system" refer to multiple components? Be explicit.

   **Check 5: Preservation Check** (ingest-specific)
   - Are all completed tasks `[x]` still present and unchanged?
   - If new context reverses completed work, is the original task preserved and the newly required migration or reversal represented by a pending task?
   - Were existing `[P]` markers preserved on tasks that still qualify?
   - Was unrelated content preserved, and was every removal or replacement of incomplete content justified by an explicit decision and recorded in the decision history?
   - Do proposal, design, delta specs, and pending tasks agree on the updated scope, without superseded instructions remaining active? Are historical records and touched task descriptions preserved?

   **Check 6: Durable Handoff Review** (run BEFORE the CLI analyzer)

   The updated change has to survive being parked or handed to another agent. Reject and fix any of the following on **incomplete** design and task content (do not rewrite completed `[x]` tasks):
   - **File-path-only tasks**: a pending task whose entire description is "edit file X" with no behavior, contract, or verification target. File paths are locator context — the task SHALL still describe what is observably true when complete.
   - **Line-number-coupled instructions**: design or task content that points to "line 42" / "the function on lines 80-95" as the only way to identify the work. Source line numbers drift; name the function, command, struct, or behavior instead.
   - **Vague acceptance criteria**: success conditions like "works correctly", "behaves as expected", "handles edge cases" without naming the observable behavior or the verification target (test name, CLI invocation, analyzer rule, manual assertion).
   - **Missing scope boundaries on non-trivial work**: design lacking explicit "in scope" / "out of scope" lines for any change that touches more than one subsystem or introduces new behavior. Trivial artifact-only edits MAY skip this; runtime, build, or tooling effects MUST NOT.

   Fix every failure inline using the existing context and the new plan/conversation source before running the CLI analyzer. Update incomplete design and task content so behavior contracts, verification criteria, and scope boundaries stay current with the new context. Preserve completed tasks unchanged.

## Artifact readiness gate

`cash-propose` 與 `cash-ingest` 在 inline self-review 後、validation 與品質關卡前 MUST 使用相同的 bounded readiness gate。這個 gate 是有限的 artifact 準備度檢查：它只在有具體修正與新證據時消耗 correction budget。

### Analyze-Fix Loop

執行 `"$cash_cli" analyze <name> --json`，並對每個 failing gate 最多兩次 correction。一次 correction 必須先指出具體 diagnostic 或新證據，實際修改受影響 artifact，再重跑同一 gate。只重跑 command、改寫 diagnostic、改變輸出 scope 或重新分類 MUST NOT 算作 progress，也 MUST NOT 重置 budget；若相同 diagnostic 沒有新進展，立即停止該 gate。

Analyze 的 diagnostic signature multiset identity 使用 `(dimension, severity, stable_location)`；`stable_location` 與 validation 的 `stable_path` 只移除 terminal `:<decimal-line>`，保留其餘 path 或 location。Analyze identity 忽略 positional `id`、finding 順序、`summary`、`recommendation` 與其他可改寫 prose；validation identity 使用 `(code, stable_path)`，忽略 finding 順序與 `message`。兩者都必須保留相同 signature 的 occurrence count；reorder、summary／recommendation／message reword、無關 line shift 或無關 bytes edit 都不算 progress。無效、無關或只改文案的 edit MUST NOT 重置 budget。只有原 occurrence 消失，或由 dimension、severity 或 stable location 不同的 signature 取代，才算該 finding 有 progress。

Suggestion 只作 advisory，先排除於 readiness 計數之外。排除 Suggestion 後，`Critical／Warnings-only／clean` 三個結果互斥且完整：有 Critical 是 Critical；沒有 Critical 但有 Warning 是 Warnings-only；兩者皆無是 clean，即使仍有 Suggestion。Warnings-only 可進入 validation 或完成摘要，但必須逐項保留，不得以「已解決」或等義文字描述。

### JSON validation gate

Analyze gate 通過後執行 `"$cash_cli" validate "<name>" --json`。Validation 也使用相同的最多兩次 correction、具體 diagnostic／新證據、實際 artifact edit、signature multiset、progress 與重複 diagnostic 停止規則；validation 未通過不得進入完成或 review 分支。

### Not-ready handoff

Critical 尚存或 validation 未通過時，第一段先回報 `not ready`，再列出 locations、原因與下一步。此 not-ready branch 優先於通用完成或 handoff fallback；不得顯示 ready completion、提供開始實作選項或 invoke `cash-apply`。

## Grounded artifact claims

在 proposal、design 或 task 寫下 grounded code-facing claims（現有 code、tests、configuration 或 runtime behavior）前，先讀取 claim 具名的最小來源範圍，並保存 path 與 symbol、heading 或 command；line number 不得是唯一定位。找不到支持時，移除事實斷言，或改寫為待驗證 task，或在會改變 contract／scope 時詢問使用者；不能把推測寫成事實。

Artifact 中的 size、count、duration、percentage、frequency 或 performance 數字必須標為 `measured`、`estimated` 或使用者／規格直接指定的 contract value。`measured` 必須記錄 observation method 與 result source；`estimated` 必須具名可確認或推翻該數字的 measurement，並列出依賴該估算的決策。

## Reader-facing output contract

四個 workflow 的 user-visible status、question、heading 與 summary MUST 先說明結果與下一步，再提供 diagnostics、locations 與其他證據。Cash 內部術語首次出現時，必須用一句繁體中文說明它對使用者的意義。固定 user-visible literals 使用繁體中文：`使用計畫檔`、`使用對話內容`、`完成`、`開始實作`、`使用 change：`、`仍要繼續`、`停止`、`修正後繼續`、`繼續執行…`、`實作完成`、`本次完成`、`實作已暫停`、`遇到的問題`、`Artifacts 一致`、`發現 N 個問題，正在修正（第 M/2 次）`、`使用 TDD`、`不使用 TDD`。commands、paths、identifiers、schema fields 與 quoted source text MUST 保持 verbatim；不得以 emoji、顏色或僅有格式差異承載唯一狀態。

8. **Validation**

   ```bash
   "$cash_cli" validate "<name>" --json
   ```

   Read the JSON result. If validation fails after the bounded correction budget, use the `not ready` handoff above: report locations, reasons and next steps, do not show `完成`／`開始實作`, and do not invoke `$cash-apply`. Show the completion choices only when validation has passed.

9. **Summary and next steps**

   Show:
   - Source used: plan file (`<path>`) or conversation context
   - Change name and location
   - Artifacts created/updated
   - Validation result

   Use **AskUserQuestion tool** to confirm the workflow is complete. This ensures the workflow stops even when auto-accept is enabled. Provide exactly these options:
   - **第一個選項（會自動選取）**：`完成` — 結束 ingest workflow，告知使用者準備好後可執行 `$cash-apply <change-name>`。
   - **第二個選項**：`開始實作` — invoke `$cash-apply <change-name>` 開始實作。

   If **AskUserQuestion tool** is not available, display the summary and inform the user to run `$cash-apply <change-name>` when ready. Then STOP — do not continue.

   **使用者回覆後**，若選擇 `完成`，workflow 結束；若選擇 `開始實作`，invoke `$cash-apply <change-name>` 開始實作。

**Guardrails**

- **NEVER** modify the original plan file, regardless of its resolved location
- **NEVER** write application code — this skill only creates/updates Cash artifacts
- **NEVER** create new changes — ingest only updates existing changes. If no active change exists, direct user to `$cash-propose`
- **NEVER** skip the artifact workflow to write code directly
- If **AskUserQuestion tool** is not available, ask the same questions as plain text and wait for the user's response

## Context and dependency handoff

For every artifact update, fetch the full instructions and retain `contextRef`; if the reference changes, is missing or malformed, discard the reused context and fetch the full instructions again. Apply the returned `rules` and `template` while preserving completed content and the user's intent. `contextRef` does not substitute for source, test, configuration or environment evidence.

Read `schema` and `task_order` from `.openspec.yaml` before updating `tasks.md`. Missing `task_order` means `document`; `dependency` tasks use `[after: 1.1, 1.2]` after the task label. Preserve task labels, exact checkbox descriptions, completed history and existing `[P]` markers; CLI ordinals are recalculated from the current task list and are not stable identity. When a requirement changes dependencies or scope, update the affected task graph together and send contract changes through `$cash-ingest` rather than silently changing execution behavior.

### Artifact context reuse

Cache only the full artifact context under the key `(canonical project root, change, schema, runtime version)`. The first artifact call has no `--omit-context`. On later calls, use `"$cash_cli" instructions <artifact-id> --change "<name>" --omit-context --json` only when that full context remains available; compare the returned `contextRef` before reuse. A changed, missing or malformed ref, unknown runtime version, different key or compaction loss requires a fresh full artifact instruction call. Always consume newly returned rules, template, dependencies and other dynamic fields. Context identity is never execution evidence.
