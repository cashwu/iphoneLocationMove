---
name: cash-ingest
description: "Update an existing Cash change from external context"
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

**Plan file support** is available when the tool has a plan directory (`~/.claude/plans/`). Otherwise, use conversation context to update artifacts.

**Prerequisites**: The project-local launcher initialized above is required. If root resolution, launcher validation, or a Cash command fails, report the exact error and STOP.

**Input**: Optionally specify an existing change name, or a plan file path or name. An existing change name selects the update target and uses conversation context as the requirement source.

- `/cash-ingest ~/.claude/plans/agile-discovering-rocket.md`
- `/cash-ingest agile-discovering-rocket`
- `/cash-ingest` (use conversation context or auto-detect plan file)

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

**Steps**

1. **Locate the requirement source**

   First, when an argument is provided, run `"$cash_cli" list --json` and `"$cash_cli" list --parked --json`. If it exactly matches an active or parked change name, retain that explicit target and use conversation context, then go to Step 3. This change-name match takes precedence over plan-file resolution below; an explicit path such as `./update-plan.md` selects a plan instead. If the context lacks the requested update, ask for that information; do not interpret the selected change as a missing plan file.

   a. **Argument provided** → treat as plan file reference (prepend `~/.claude/plans/` and append `.md` if needed)
   - If the file exists → use it as the plan file source, proceed to Step 2
   - If the file does NOT exist → report the error and **stop**

   b. **No argument, plan file detectable**:
   - Check conversation context for plan file path (plan mode system messages include the path like `~/.claude/plans/<name>.md`)
   - If found and the file exists → use the **AskUserQuestion tool** to ask:
     - Option 1: Use the plan file
     - Option 2: Use conversation context
   - If the user picks plan file → proceed to Step 2
   - If the user picks conversation context → skip Step 2, go to Step 3

   c. **No argument, no plan file detectable**:
   - Check `~/.claude/plans/` for recent files
   - If recent files exist → list 5 most recent with the **AskUserQuestion tool**, include "Use conversation context" as an additional option
   - If the user picks a file → proceed to Step 2
   - If the user picks conversation context → skip Step 2, go to Step 3

   d. **Conversation context fallback** (no plan files found at all):
   - Use conversation context to update artifacts
   - If conversation context is insufficient, use the **AskUserQuestion tool** to get more details
   - Warn: "No plan file found. Using conversation context."

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
   - If no changes at all (neither active nor parked) → tell the user: "No active change found. Use `/cash-propose` first to create one." and **stop**

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

   **Parallel task markers (`[P]`)**: When creating or updating the **tasks** artifact, first read `.cash.yaml`. If `parallel_tasks: true` is set, add `[P]` markers to new tasks that can be executed in parallel. Format: `- [ ] [P] Task description`. A task qualifies for `[P]` if it targets different files from other pending tasks AND has no dependency on incomplete tasks in the same group. When `parallel_tasks` is not enabled, do NOT add `[P]` markers — but still preserve any existing `[P]` markers already in the file.

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

7. **Analyze-Fix Loop** (max 2 iterations)

   ```bash
   "$cash_cli" analyze <name> --json
   ```

   1. Filter findings to **Critical and Warning only** (ignore Suggestion)
   2. If no Critical/Warning findings → show "Artifacts look consistent ✓" and proceed
   3. If Critical/Warning findings exist:
      a. Show: "Found N issue(s), fixing... (attempt M/2)"
      b. Fix each finding in the affected artifact
      c. Re-run `"$cash_cli" analyze <name> --json`
      d. Repeat up to 2 total iterations
   4. After 2 attempts, if findings remain:
      - Show remaining findings as a summary
      - Proceed normally (do NOT block)

8. **Validation**

   ```bash
   "$cash_cli" validate "<name>"
   ```

   If validation fails, fix errors and re-validate.

9. **Summary and next steps**

   Show:
   - Source used: plan file (`<path>`) or conversation context
   - Change name and location
   - Artifacts created/updated
   - Validation result

   Use **AskUserQuestion tool** to confirm the workflow is complete. This ensures the workflow stops even when auto-accept is enabled. Provide exactly these options:
   - **First option (will be auto-selected)**: "Done" — End the ingest workflow. Inform the user they can run `/cash-apply <change-name>` when ready.
   - **Second option**: "Apply" — Invoke `/cash-apply <change-name>` to start implementation.

   If **AskUserQuestion tool** is not available, display the summary and inform the user to run `/cash-apply <change-name>` when ready. Then STOP — do not continue.

   **After the user responds**, if they chose "Done", the workflow is OVER. If they chose "Apply", invoke `/cash-apply <change-name>` to begin implementation.

**Guardrails**

- **NEVER** modify the original plan file in `~/.claude/plans/`
- **NEVER** write application code — this skill only creates/updates Cash artifacts
- **NEVER** create new changes — ingest only updates existing changes. If no active change exists, direct user to `/cash-propose`
- **NEVER** skip the artifact workflow to write code directly
- If **AskUserQuestion tool** is not available, ask the same questions as plain text and wait for the user's response
