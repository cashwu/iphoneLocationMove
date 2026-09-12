---
name: cash-drift
description: "Detect drift between a Cash change and the current codebase state. Use when an existing change may be stale or out of sync with the repository."
argument-hint: "[change-name]"
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

Detect drift between a Cash change and the current codebase state. Reports time dormancy, broken design anchors, task collisions with external commits, and a single recommended next command.

**Input**: Optionally specify a change name (e.g., `$cash-drift add-auth`). If omitted, infer from conversation context or auto-select if only one active change exists.

**Prerequisites**: This skill requires the `Cash` CLI. If any `Cash` command fails with "command not found" or similar, report the error and STOP.

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

**Steps**

1. **Determine change name**

   If not provided, infer from context or run `"$cash_cli" list --json` to auto-select. If multiple active changes exist and no name is given, list candidates and ask the user to rerun with an explicit name.

2. **Run programmatic drift analysis**

   ```bash
   "$cash_cli" drift <change-name> --json
   ```

   The JSON contains:
   - `severity`: `"light"` / `"medium"` / `"heavy"`
   - `total_score`: aggregate over Time / Structure / Tasks (Environment is display-only)
   - `dimensions`: array of `{ kind, status, score, contributes_to_total }`
   - `broken_anchors`: design.md references (file paths / symbols / functions / CLI flags) that no longer resolve
   - `tasks_blocked_external`: pending tasks whose referenced files were modified by commits outside the change dir
   - `tasks_maybe_resolved`: pending tasks whose verb+target keywords match commit subjects since `created`
   - `dormancy`: the CLI-owned `{status, reason, age_days, idle_days}` evidence
   - `recommended_action`: the CLI-owned `{action_kind, change_name, flags}` routing object
   - `primary_recommendation`: a legacy rendering of the structured action; display only, never a routing source

3. **Present the report**

   Use a user-readable, conclusion-first format. The first substantive paragraph after the title MUST be a plain-language conclusion that says what to do next before showing score tables, broken anchors, task collisions, or severity labels.

   Translate severity into action-oriented meaning:
   - **Light**: the change can continue with apply.
   - **Medium**: the change can continue, but the plan should be refreshed before implementation.
   - **Heavy**: the old plan is likely unsuitable for direct implementation; restart or refresh first.

   Recommended shape:

   ```markdown
   ## Drift Report: <change-name>

   <Plain-language conclusion. Example for medium: "This change can continue, but update the plan before implementing it. Related code has changed since the plan was written, so applying the old tasks directly may cause rework or conflicts.">

   ### Why

   - <1-3 plain-language reasons derived from dimensions, broken anchors, and task collisions>

   ### Details

   | Item              | Result                                                 |
   | ----------------- | ------------------------------------------------------ |
   | Time              | <status>                                               |
   | Design references | <broken anchor count or "No broken references">        |
   | Pending tasks     | <blocked/maybe-resolved count or "No task collisions"> |
   | Overall           | <light/medium/heavy, total score N>                    |

   ### Recommendation

   Recommended next skill: `<primary_recommendation>`
   ```

   Keep technical details below the plain-language conclusion. List broken anchors, blocked tasks, and maybe-resolved tasks only when non-empty. Omit empty technical detail sections entirely. Keep the report short enough to skim; the goal is to help the user decide, not to explain the scoring model.

4. **Validate and route the structured action**

   Read `recommended_action` as the only follow-up routing source. Before using it, verify that the object has exactly these keys: `action_kind`, `change_name`, and `flags`; `action_kind` is exactly `apply` or `ingest`; `change_name` is non-empty and equals the JSON `change_id`; and `flags` is exactly an empty array. A non-empty array, unknown key, unknown action, empty name, or mismatched name is malformed.

   For malformed structured action, report `Malformed structured action` and fail closed. Stop immediately and do not parse or execute `primary_recommendation`. The legacy field may be displayed as evidence only; it is never a routing authority.

   After shape validation, render the action with this variant's invocation prefix and present explicit choices. In a main-thread flow, use the **AskUserQuestion tool**, preserve the exact command in each option description, and wait for explicit user authorization before executing it. MUST NOT execute `apply` or `ingest` before authorization. If the AskUserQuestion tool is unavailable, ask the same options in plain text and wait.

   - `action_kind: apply`: label the option "Directly start work" and describe `$cash-apply <name>`.
   - `action_kind: ingest`: label the option "Refresh the plan" and describe `$cash-ingest <name>` with the drift findings as context.
   - An alternate "Pause for now" option does nothing until the user decides.

   In the report-only fork, return the validated recommendation and evidence to the main thread. The fork MUST NOT execute the action or ask or wait for the user.

**Dormancy evidence**

Use the CLI-provided `dormancy` object as evidence only. `cash-drift` MUST NOT read change dates, query Git history, recompute thresholds, or create a second dormancy decision.

**Guardrails**

- Read-only: NEVER modify files, artifacts, or git state based on drift findings
- If `"$cash_cli" drift` returns a non-zero exit code or an invalid response, report the execution error and stop
