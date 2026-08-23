---
name: cash-archive
description: "Archive a completed change"
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

Archive a completed change.

**Input**: Optionally specify a change name after `/cash-archive` (e.g., `/cash-archive add-auth`), optionally followed by `--skip-specs` to explicitly request skipping delta spec sync (see step 4). If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

**Prerequisites**: The project-local launcher initialized above is required. If root resolution, launcher validation, or a Cash command fails, report the exact error and STOP.

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

**Steps**

1. **If no change name provided, prompt for selection**

   Run `"$cash_cli" list --json` to get available changes. Use the **AskUserQuestion tool** to let the user select.

   Show only active changes (not already archived).
   Include the schema used for each change if available.

   **IMPORTANT**: Do NOT guess or auto-select a change. Always let the user choose.

2. **Check artifact completion status**

   Run `"$cash_cli" status --change "<name>" --json` to check artifact completion.

   Parse the JSON to understand:
   - `schemaName`: The workflow being used
   - `artifacts`: List of artifacts with their status (`done` or other)

   **If any artifacts are not `done`:**
   - Display warning listing incomplete artifacts
   - Prompt user for confirmation to continue
   - Proceed if user confirms

3. **Check task completion status**

   Read the tasks file (typically `tasks.md`) to check for incomplete tasks.

   Count tasks marked with `- [ ]` (incomplete) vs `- [x]` (complete).

   **If incomplete tasks found:**
   - Display warning showing count of incomplete tasks
   - Use the **AskUserQuestion tool** to ask: "These tasks are still incomplete. Mark all as complete before archiving?"
     - **Yes**: set a flag to pass `--mark-tasks-complete` to the archive command in step 5
     - **No**: stop without archiving; do not invoke archive with incomplete tasks

   **If no tasks file exists:** Proceed without task-related warning.

4. **Determine spec sync behavior**

   Check for delta specs at `openspec/changes/<name>/specs/` — they do not exist when the directory is empty or absent — then resolve the flag without asking the user.

   - **Explicit skip**: pass `--skip-specs` only when the user asked to skip delta spec sync in this invocation — either by appending `--skip-specs` to the invocation, or by saying so directly in this session. This takes precedence over the default below.
   - **Default — sync**: otherwise run archive without `--skip-specs`, whether or not delta specs exist, and do NOT ask the user to choose.
   - MUST NOT infer a skip request from the change looking tooling-only or doc-only, from an earlier archive, or from any other indirect signal.
   - Record the resolved outcome by evaluating in order: `skipped` (the flag is set), then `synced` (delta specs exist and the flag is not set), then `no delta specs` (no delta specs and the flag is not set); step 6 reports it.

   Do not invoke another skill or delete touched state directly. The Cash CLI owns touched import, sync state, legacy cleanup diagnostics, transaction flags, and cleanup.

5. **Perform the archive**

   Use the `"$cash_cli" archive` command, adding the resolved flags:

   ```bash
   "$cash_cli" archive <name>
   "$cash_cli" archive <name> --skip-specs
   "$cash_cli" archive <name> --mark-tasks-complete
   ```

   **Optional flags:**
   - `--skip-specs` — skip delta spec application; use only on the explicit request described in step 4
   - `--mark-tasks-complete` — mark all incomplete tasks as complete before archiving
   - `--no-validate` — skip the independent change validation gate only; safety and delta identity preflight remain mandatory

   **If archive fails** with "already exists" error, suggest renaming existing archive.

   **If archive fails** on delta parse or `requirement_identity_mismatch`, report the exact error and fix the delta specs before re-running. `--skip-specs` does NOT bypass either check.

   **If archive fails** with `validation_failed`, report the exact error and give both ways forward: fix the validation findings and re-run, or re-run with `--no-validate` once the findings are judged acceptable. `--skip-specs` does NOT bypass this gate either.

   **If archive fails** with `tasks_incomplete`, report the exact error and re-run with `--mark-tasks-complete`; neither `--skip-specs` nor `--no-validate` bypasses this precondition.

   **If archive fails** with `touched_invalid` naming a `task_desc` that no longer exists in `tasks.md`, determine whether that task was renamed or removed. If renamed, update that entry's `task_desc` in `.cash-skills/state/touched/<name>.json` to the task's current description, then re-run archive. Editing `task_desc` to repair a rename is the one permitted manual edit to touched state; never delete the file. If removed, stop and run `/cash-ingest` with the current `touched_invalid` error and change name as conversation context so it selects the existing change and restores the exact `task_desc` as a completed `[x]` task in `tasks.md`, then re-run archive; do not edit or delete the touched entry, because its `files` remain attributed to that historical task. If restoring the exact `task_desc` would cause a task label conflict, stop and use `/cash-ingest` with the same conversation context to resolve the artifact conflict; do not guess a new label or reattribute `files`.

6. **Display summary**

   Show archive completion summary including:
   - Change name
   - Schema that was used
   - Archive location
   - Spec sync status: `synced`, `skipped`, or `no delta specs` — the `**Specs:**` line reports `✓ Synced to main specs`, `Sync skipped (explicitly requested by the user)`, or `No delta specs` respectively
   - Any legacy cleanup diagnostic returned by Cash; report it as a diagnostic only and do not re-read legacy state
   - Note about any warnings (incomplete artifacts/tasks, or a `skipped` outcome)

   **Template selection**: use the **Output On Success With Warnings** template whenever there is at least one warning; an outcome of `skipped` is itself a warning. Include the skipped warning line only when the outcome is `skipped`.

**Output On Success**

```
## Archive Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** ✓ Synced to main specs

All artifacts complete. All tasks complete.
```

**Output On Success (No Delta Specs)**

```
## Archive Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** No delta specs

All artifacts complete. All tasks complete.
```

**Output On Success With Warnings**

```
## Archive Complete (with warnings)

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** <✓ Synced to main specs | Sync skipped (explicitly requested by the user) | No delta specs>

**Warnings:**
- Archived with 2 incomplete artifacts
- Archived with 3 incomplete tasks
- Delta spec sync was skipped (explicitly requested by the user)

Review the archive if this was not intentional.
```

**Output On Error (Archive Exists)**

```
## Archive Failed

**Change:** <change-name>
**Target:** openspec/changes/archive/YYYY-MM-DD-<name>/

Target archive directory already exists.

**Options:**
1. Rename the existing archive
2. Delete the existing archive if it's a duplicate
3. Wait until a different date to archive
```

**Guardrails**

- Preserve .openspec.yaml when moving to archive (it moves with the directory)
- Never delete touched or sync state directly; archive owns ensure, transaction, cleanup, and each legacy cleanup diagnostic
- If **AskUserQuestion tool** is not available, ask the same questions as plain text and wait for the user's response
