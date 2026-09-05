---
name: cash-drift
description: "Detect drift between a Cash change and the current codebase state"
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
   - `primary_recommendation`: the recommended Cash skill name and change name

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

4. **Apply the recommendation interactively**

   Use the **AskUserQuestion tool** to offer one decision based on `severity`. Use plain-language option labels while preserving the exact command in each option description. Do NOT auto-invoke `$cash-apply`, `$cash-ingest`, or `"$cash_cli" archive`; always wait for the user's choice.
   Use the returned `severity` as the routing authority; do not recompute severity from score or anchor percentages. The current CLI thresholds are light below 30, medium from 30 to below 60, and heavy at 60 or above.
   - **Light** (drift is minor):
     - Recommended label: "Directly start work"
       - Description: run `$cash-apply <name>`
     - Alternate label: "Pause for now"
       - Description: do nothing until the user reviews manually
   - **Medium** (refresh worth doing):
     - Recommended label: "Refresh the plan"
       - Description: run `$cash-ingest <name>` with the broken references and task collisions as context
     - Alternate label: "Directly start work"
       - Description: run `$cash-apply <name>` only if the user knows the reported changes are harmless
     - Alternate label: "Pause for now"
       - Description: do nothing until the user reviews manually
   - **Heavy** (design diverges from code):
     - Recommended label: "Refresh the plan"
       - Description: run `$cash-ingest <name>` with the drift findings as context, matching the CLI's `primary_recommendation`. This updates the existing change; it does not archive or restart it.
     - Alternate label: "Pause for now"
       - Description: do nothing until the user reviews manually

**Passive Trigger**

When `$cash-apply` is invoked on a change whose `.openspec.yaml created` date is more than 5 days ago AND no commits have touched the change directory in the past 3 days, the apply skill SHOULD run drift analysis first and surface findings before tasks begin. The trigger is guidance only and MUST NOT block apply from proceeding.

(Threshold reasoning: AI-assisted commits are daily-cadence, not weekly. A change sitting ≥5 days with ≥3 days of no commits is almost always genuine stagnation rather than normal pacing.)

**Guardrails**

- Read-only: NEVER modify files, artifacts, or git state based on drift findings
- If `"$cash_cli" drift` returns a non-zero exit code or an invalid response, report the execution error and stop
- If **AskUserQuestion tool** is not available, ask the same questions as plain text and wait for the user's response
