---
name: cash-apply
description: Implement Cash tasks with a sub-agent quality gate after completion
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

Implement tasks from a Cash change.

**Input**: Optionally specify a change name (e.g., `$cash-apply add-auth`). If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

**Task tracking is file-based only.** The tasks file's markdown checkboxes (`- [ ]` / `- [x]`) are the single source of truth for progress. Do NOT use any external task management system, built-in task tracker, or todo tool. When a task is done, edit the checkbox in the tasks file — that is the only way to record progress.

**Prerequisites**: The project-local launcher initialized above is required. If root resolution, launcher validation, or a Cash command fails, report the exact error and STOP.

**Steps**

1. **Select the change**

   If a name is provided, use it. Otherwise:
   - Infer from conversation context if the user mentioned a change
   - Auto-select if only one active change exists
   - If ambiguous, run `"$cash_cli" list --json` AND `"$cash_cli" list --parked --json` to get all available changes (including parked ones). Parked changes should be annotated with "(parked)" in the selection list. Use the **AskUserQuestion tool** to let the user select

   Always announce: "Using change: <name>" and how to override (e.g., `$cash-apply <other>`).

   If the AskUserQuestion tool is unavailable, ask the same question or options in plain text and wait for the user's response.

2. **Check status to understand the schema**

   ```bash
   "$cash_cli" status --change "<name>" --json
   ```

   **If the command fails**: show the error and STOP.

   **If the command succeeds**, check whether the change is parked (status can succeed even for parked changes):

   ```bash
   "$cash_cli" list --parked --json
   ```

   Look for the change name in the `parked` array of the JSON output.
   - **If the change IS in the parked list** (it's parked):
     Inform the user that this change is currently parked（暫存）.
     Use the **AskUserQuestion tool** to ask whether to continue.
     Two options:
     - **Continue**: Unpark the change and proceed with apply
     - **Cancel**: Stop the workflow

     If the user chooses to continue:

     ```bash
     "$cash_cli" unpark "<name>"
     ```

     Then mark it as in-progress:

     ```bash
     "$cash_cli" in-progress add "<name>"
     ```

     This is a silent operation — do not show the output to the user.

     Then re-run `"$cash_cli" status --change "<name>" --json` and continue normally.

   - **If the change is NOT in the parked list**: mark it as in-progress and proceed normally.

     ```bash
     "$cash_cli" in-progress add "<name>"
     ```

     This is a silent operation — do not show the output to the user.

   Parse the JSON to understand:
   - `schemaName`: The workflow being used (e.g., "spec-driven")
   - Which artifact contains the tasks (typically "tasks" for spec-driven, check status for others)

3. **Get apply instructions**

   ```bash
   "$cash_cli" instructions apply --change "<name>" --json
   ```

   This returns:
   - Context file paths (varies by schema)
   - Progress (total, complete, remaining)
   - Task list with status
   - Dynamic instruction based on current state

   **Handle states:**
   - Always read `missingArtifacts`; it is present in every state.
   - If `state: "blocked"`: show the non-empty `missingArtifacts` list and suggest using `$cash-propose` to create those artifacts first
   - If `state: "all_done"`: continue to the cash quality gate before any archive guidance
   - If `state: "ready"`: proceed to implementation
   - Any other state or missing required field is a contract error; report it and STOP.

3b. **Preflight check**

The apply instructions JSON always includes `preflight`. Treat a missing `preflight`, `missingFiles`, `driftedFiles`, or `staleness` field as a contract error. Act on `preflight.status`:

- **`"clean"`**: silently continue — no output needed.
- **`"warnings"`**: display a brief summary, then continue automatically:
  ```
  ⚠ Preflight warnings:
  - Drifted files (modified after change was created): <list paths>
  - Change is <N> days old
  Continuing...
  ```
  Only show the lines that are relevant (skip drifted if none, skip staleness if not stale).
- **`"critical"`**: display missing files with their source artifact, then use the **AskUserQuestion tool** to ask the user:

  ```
  ⚠ Preflight: missing files detected
  - <path> (referenced in <source artifact>)
  - ...
  These files are referenced in the change artifacts but no longer exist on disk.
  ```

  Options: "Continue anyway" / "Stop"
  If the user chooses "Stop", end the workflow.

3c. **Artifact quality check**

Run `"$cash_cli" analyze <change-name> --json` to check cross-artifact consistency (Coverage, Consistency, Ambiguity, Gaps).

- **Zero findings**: silently continue.
- **Warning/Suggestion only**: display a one-line summary (e.g., "⚠ Artifact analysis: 2 warnings found") and continue automatically.
- **Critical findings**: display each Critical finding (summary + location + recommendation), then use the **AskUserQuestion tool**:
  - **Fix and continue** — fix the artifact issues inline, then proceed
  - **Continue anyway** — skip fixes and start implementation
  - **Stop** — end the workflow

3d. **Drift dormancy check** (passive trigger for stale changes)

When the change has been dormant for more than 5 days AND the change directory has had zero commits in the past 3 days, surface a drift report before tasks begin — the change is likely out-of-sync with the current codebase.

Detect dormancy from `.openspec.yaml` `created` and `git log -1 --format=%at -- openspec/changes/<name>/`:

- **Both conditions met**: run `"$cash_cli" drift <change-name>`, display the report, then use the **AskUserQuestion tool**:
  - **Continue with apply** — proceed to tasks (recommended for Light drift)
  - **Refresh first** — pause apply, run `$cash-ingest <change-name>` to update artifacts, then resume
  - **Stop** — end the workflow
- **Either condition not met**: silently continue, no output.

The trigger is guidance only — it MUST NOT block apply from proceeding when the user chooses to continue. Hard-blocking on dormancy would punish legitimate "I came back after a long weekend" cases.

(Threshold reasoning: AI-assisted commits are daily-cadence. ≥5 days dormant + ≥3 days no commit ≈ genuine stagnation, not normal pacing.)

4. **Read context files**

   Read the files listed in `contextFiles` from the apply instructions output.
   The files depend on the schema being used:
   - **spec-driven**: proposal, specs, design, tasks
   - Other schemas: follow the contextFiles from CLI output

5. **Check project preferences**

   Read `.cash.yaml` in the project root.
   If `tdd: true` is set, apply TDD discipline throughout implementation:
   - For each task, write a failing test FIRST, then implement to make it pass
   - Fetch TDD instructions by running `"$cash_cli" instructions --skill tdd`, then follow the Red-Green-Refactor cycle
   - For bug fixes, reproduce the bug with a failing test before fixing

   If `audit: true` is set, apply sharp-edges discipline throughout implementation:
   - When designing APIs or interfaces, evaluate through 3 adversary lenses (Scoundrel, Lazy Developer, Confused Developer)
   - When adding configuration options, verify defaults are secure and zero/empty values are safe
   - When accepting parameters, check for type confusion and silent failures
   - Fetch audit instructions by running `"$cash_cli" instructions --skill audit`, follow the discipline checklist (not the standalone 3-agent workflow)

   If `parallel_tasks: true` is set, check whether consecutive pending tasks have `[P]` markers (format: `- [ ] [P] Task description`). You SHALL dispatch consecutive `[P]` tasks as parallel agents. Only fall back to sequential when tasks have a data dependency (one task's output is another's input) or when tasks modify overlapping regions of the same file. Targeting the same file alone is NOT a reason to skip parallel dispatch — if the modified regions are disjoint, dispatch in parallel. If the environment does not support parallel execution, ignore `[P]` markers and execute tasks sequentially.

6. **Show current progress**

   Display:
   - Schema being used
   - Progress: "N/M tasks complete"
   - Remaining tasks overview
   - Dynamic instruction from CLI

7. **Implement tasks (loop until done or blocked)**

   **Reminder: Track progress by editing checkboxes in the tasks file only. Do not use any built-in task tracker.**

   For each pending task:
   - Show which task is being worked on
   - Re-read the sections of design and spec files that are relevant to this task's scope — do not rely on memory from earlier in the conversation, as context may have been compressed
   - **Read the Implementation Contract for this task before editing any source file.** If `design.md` exists and contains an `## Implementation Contract` section (or contract content under another heading the design uses), read the part of it that covers this task's scope. The contract names the observable behavior, interface or data shape, failure modes, acceptance criteria, and scope boundaries you must satisfy. Treat the contract as the durable handoff — it is what the task will be measured against, regardless of who started the change.
   - **Detect unclear or path-only tasks before writing code.** A task is unclear if it:
     - only names files to edit ("edit `foo.rs`", "update `bar.svelte`") with no behavior, contract, or verification target;
     - is vague ("handle edge cases", "wire it up", "make it work");
     - conflicts with the implementation contract (asks for behavior the contract excludes, or omits behavior the contract requires).
       When this happens, pause. Either update the artifact (design or tasks) so the task names a concrete behavior and verification target, or report the blocker and wait for guidance. Do NOT silently guess against unclear requirements.
   - Before writing code, check:
     1. **Reuse** — search adjacent modules and shared utilities for existing implementations before writing new code
     2. **Quality** — derive values from existing state instead of duplicating; use existing types and constants over new literals
     3. **Efficiency** — parallelize independent async operations; avoid unnecessary awaits; match operation scope to actual need
     4. **No Placeholders in artifacts** — if the design or spec for this task contains placeholder language (TBD, TODO, "add appropriate handling"), pause and fix the artifact first or flag to the user. Do not implement against vague requirements.
     5. **Examples as verification** — if the spec for this task's scope includes `##### Example:` blocks, use them as concrete test cases:
        - When TDD is enabled: derive the first failing test directly from the example's GIVEN/WHEN/THEN values
        - When TDD is not enabled: after implementing, verify the code handles the example's input→output correctly
        - Example tables map to parameterized tests — one test per row
          Do NOT invent additional test values beyond what the spec examples provide without reason. The examples ARE the agreed specification.
   - Make the code changes required
   - Keep changes minimal and focused
   - Write or update the relevant test before marking the task done, even when TDD is disabled or the task is a small refactor
   - **Verify before marking done** — re-read the task description from the tasks file AND the relevant Implementation Contract content from design.md. For each requirement stated in the task description and each contract item that covers this task's scope, confirm it is addressed by your changes. Confirm the verification target named by the task (test name, CLI invocation, analyzer check, or manual assertion) actually passes. If any contract item, task requirement, or verification target is missing or failing, implement/fix it now. Do not mark the task complete until every part of the description is covered and the contract for this task is satisfied.
   - Mark task complete by running: `"$cash_cli" task done --change "<name>" <task-id>`
     This command marks the checkbox in tasks.md AND records which files were modified for this task.
   - Continue to next task

   **Parallel task dispatch**: When consecutive `[P]`-marked tasks are found and `parallel_tasks: true` is configured (see Step 5), dispatch them as parallel agents in a single message. If any `[P]` task fails, pause and report.

   **Pause if:**
   - Task is unclear → ask for clarification
   <!-- BLOCKER-TRIAGE -->
   - **繼續分支（機制替換，contract 不變）**：原設計指定的達成手段在目標平台或現實不可行，但要交付的觀察行為、interface／資料形狀、失敗模式與驗收標準都不變，且替代手段不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md` → 依 Implementation Notes Protocol 記一筆 `deviation`，說明原手段與替代手段，然後繼續該 task，不暫停、不要求 `$cash-ingest`。當上述條件全部成立時，即使需要在多個都保留 contract 的替代手段之間選擇，也 SHALL 以記一筆 `deviation` 解決，不觸發暫停分支。
   - **暫停分支（contract／範圍／行為變更）**：阻塞改變要交付的觀察行為、範圍或使用者可見的取捨，或替代手段需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`，或存在其解答可能改變 contract 或範圍、需要使用者決定的 open question → 暫停、報告 blocker，並引導使用者前往 `$cash-ingest`。
   - Other errors or blockers not covered by the blocker triage above → report and wait for guidance
   - User interrupts

**Focused Implementation Discipline**

- 只實作 `tasks.md` 任務描述與 `design.md` Implementation Contract 要求的功能；不要為單一使用情境引入抽象層、設定選項或額外彈性，也不要為 contract 已排除或型別已保證的情境撰寫防禦性錯誤處理——只在系統邊界（外部輸入、外部 API）驗證。
- 只修改任務直接需要的區塊，不順手改鄰近內容，也不重構沒有問題的既有程式碼；即使既有風格與你習慣不同也跟著現況走（match existing style），且只清除因本次改動而變成 orphan 的 import、變數與函式。
- 若注意到不相關的死碼、bug 或可改進處，不要直接刪或改；依 Implementation Notes Protocol 在 `implementation-notes.md` 以 `open-question` 條目記錄，交給使用者決定。
- 驗收標準：本次 diff 的每一行，都能直接追溯到 `tasks.md` 中的某條任務或 `design.md` 中的 Implementation Contract 項目。
- 以 future-self 或 reviewer 能在幾秒內理解每行意圖為清晰度判準；clarity 永遠優先於 brevity。
- 違反上述任一條視同 task 未完成，在執行 `"$cash_cli" task done` 之前先修正。若刻意 deviate，依 Implementation Notes Protocol 寫一筆 `deviation` 條目並說明原因。

8. **Implementation Notes Protocol**

   During the cash-apply task loop, maintain a lightweight running log at `openspec/changes/<change>/implementation-notes.md` that captures only two categories of information:

   - **Deviations**: places where the implementation intentionally departs from `spec.md`, `design.md`, or `tasks.md` (because the spec was ambiguous, the codebase reality differs, or a discovered issue forced a different path).
   - **Open questions**: items that need user confirmation or revision before this change can be considered complete.

   Design decisions that match the spec, ordinary tradeoffs, and small judgment calls do NOT belong here — they are already covered by `design.md`, `tasks.md`, and the review-loop round files. Keep this log narrow.

   **File creation rule (eager)**
   - At the start of Step 7 (the task loop), before processing the first task, create `openspec/changes/<change>/implementation-notes.md` if it does not already exist.
   - Initialize the file with a single-line HTML comment header (and nothing else):
     ```
     <!-- cash-apply implementation notes | change: <change-name> | initialized: <YYYY-MM-DD HH:MM> | no entries below means no deviations or open questions were recorded -->
     ```
   - Entries (see below) are appended in order beneath this header.
   - Eager creation makes "no entries" an explicit positive signal (cash-apply ran and found nothing to report), distinct from file-absent which signals a workflow integrity failure.

   **Entry format**

   Each entry MUST be appended (never rewriting earlier entries) using this exact structure:

   ```
   ## <YYYY-MM-DD HH:MM> — <short title>
   - 類別：deviation | open-question
   - 任務：<task-id or "n/a">
   - 內容：<one-paragraph description of what happened or what needs answering>
   - 原因：<why this path was chosen, or why the user needs to weigh in>
   ```

   Prose (`內容`, `原因`, title) is written in Traditional Chinese, matching the cash-apply response-language rule. CLI commands, file paths, code identifiers, capability slugs, and quoted source text remain verbatim in English.

   **When to write an entry**
   - When task-level implementation diverges from `design.md` Implementation Contract, `tasks.md` description, or relevant `spec.md` requirements — write a `deviation` entry before marking the task done.
   - When the task surfaces a question the user must decide (e.g. ambiguous requirement, missing schema field, contested naming) and the agent has to proceed under an assumption — write an `open-question` entry naming the assumption.
   - Do not batch entries to the end of the session; record at the moment the decision is made, while context is fresh.

   **When NOT to write an entry**
   - Routine implementation that matches the artifacts — no entry.
   - Trivial naming or formatting choices — no entry.
   - Anything already documented in `design.md` or the round-`<N>` review files — no entry.

   **Sub-agent reviewer requirement**

   Reviewer A — Adherence in the Sub-Agent Review/Rating/Fix Loop MUST, at the start of each full round, read `openspec/changes/<change>/implementation-notes.md`. In each micro round, Reviewer V MUST read the same file before verifying fixes.

   - **File absent**: this is a Critical finding — cash-apply failed to initialize the running log, indicating either an aborted workflow or a skill-integrity failure. The round MUST NOT pass; recommend re-running cash-apply or back-filling the file before the next round.
   - **File present with only the initialization comment and no entries**: treat as confirmed empty — cash-apply reached the task loop and found nothing requiring a `deviation` or `open-question` entry. No finding raised by virtue of emptiness alone.
   - **File present with entries**:
     - `deviation` entries are evaluated for whether the divergence is justified. An unjustified deviation is a Critical finding; a justified-but-undocumented-in-`design.md` deviation is at minimum a Warning recommending the divergence be back-filled into `design.md` during Fix Actions.
     - `open-question` entries are surfaced as Warning findings with a recommended `## Fix Actions` step naming how to obtain user confirmation before the round can pass.

   The main agent derives the round decision mechanically from the post-filter reviewer findings and does not read this file directly; that round's reviewer findings already incorporate the notes context.

   **Idempotence and ingest interaction**
   - `$cash-ingest` may modify `tasks.md` / `design.md` / `proposal.md`. After ingest resolves an open question, the agent MUST append a follow-up entry noting the resolution (do not delete or rewrite the original `open-question` entry — the historical record is the point).
   - Reviewer treats a resolved `open-question` entry (i.e. one followed by a resolution entry) as no longer blocking.

9. **Final check**

   After completing all tasks, re-run:

   ```bash
   "$cash_cli" instructions apply --change "<name>" --json
   ```

   Confirm `state: "all_done"`. If not, review remaining tasks and complete them.

10. **On completion or pause, show status**

   Display:
   - Tasks completed this session
   - Overall progress: "N/M tasks complete"
   - If all done: state that tasks are complete; archive guidance is deferred until the cash quality gate passes
   - If paused: explain why and wait for guidance



**Cash-apply response language**

   All user-facing AI responses during this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names (`applyRequires`, `outputPath` 等), artifact IDs, capability slugs, technical names, and quoted source text verbatim.

   **Artifact modifications during cash-apply**

   When the cash-apply workflow modifies an artifact — during review-loop fix actions, or after `$cash-ingest` updates `tasks.md` / `design.md` / `proposal.md` — the updated artifact content MUST follow the same Chinese language rule as cash-propose:

   - `tasks.md`, `design.md`, `proposal.md`, and other non-spec artifacts under `openspec/changes/<change>/`: Traditional Chinese.
   - Spec files (`openspec/changes/<change>/specs/**/spec.md` and `openspec/specs/**/spec.md`): follow the Spec-file language policy — Traditional Chinese prose with English structural keywords (`### Requirement:`, `#### Scenario:`, GIVEN/WHEN/THEN/AND) and English normative verbs (SHALL / MUST and their NOT forms) embedded in Chinese sentences. Every MODIFIED/REMOVED requirement title and every RENAMED FROM title MUST be copied byte-for-byte from the current master spec, because `"$cash_cli" archive` matches titles verbatim and fails closed with `requirement_identity_mismatch` when a title does not match.

   Keep CLI commands, file paths, code identifiers, schema field names, artifact IDs, capability slugs, and existing quoted source text verbatim. If the user explicitly requests another language later, follow the latest user instruction.

   **Archive guidance timing**

   Do not suggest archive before the Sub-Agent Review/Rating/Fix Loop has ended with `decision: passed`.

   - If the final round decision is `passed`, the final response MAY tell the user they can archive with `$cash-archive`. When it does, it MUST also tell them to commit first with `$cash-commit`, or to archive through the `$cash-commit` "Archive first, then commit together" sub-flow, because running `$cash-archive` on its own deletes the touched state that `$cash-commit` uses as its source allowlist, leaving it to fall back to the archive manifest's point-in-time snapshot — which does not include anything changed after archiving, and does not exist at all in archives created before that field was added.
   - If the final round decision is `aborted`, do NOT suggest archive; summarize the unresolved findings and point to the final round file.

11. **Sub-Agent Review/Rating/Fix Loop**

   Run this review/rating/fix loop once per change, after the normal workflow has completed its required artifact or task work.

   **Entry conditions**
   - For `cash-propose`, start this loop only after proposal, design, specs, and tasks artifacts required for apply are complete AND `"$cash_cli" validate "<name>"` has passed. If validation fixes are required, complete them before entering this loop.
   - For `cash-apply`, start this loop only after all implementation tasks are complete and `tasks.md 全 [x]`.
   - Do not run this loop per artifact or per task; the granularity is per-change.

   **Pre-round mechanical self-check (main agent, inline)**

   <!-- MECHANICAL-SELF-CHECK -->
   - Run this self-check inline (grep/read, no sub-agent) before spawning round 1's reviewers, and again whenever a round's fix actions modified any artifact (or, for cash-apply, any implementation file) — before spawning the next round's reviewers. Reviewer rounds are expensive; these defects are machine-catchable and MUST be caught here, not by reviewers.
   - Checks:
     - **Comment/annotation lint**: in every spec delta file, `<!--` and `-->` counts MUST match; no unclosed annotation block (e.g. a dangling `<!-- @trace` line) and no stray `---` separator may remain inside a requirement or scenario section.
     - **Count-consistency scan**: every numeric claim one artifact makes about another (e.g. proposal or design stating a scenario, requirement, or task count) MUST match the actual count in the referenced artifact. Recount at the source and update stale numbers.
     - **Identifier cross-grep**: for each function name, entry point, file path, flag, or artifact ID that `design.md` defines, grep ALL artifacts (and for cash-apply, the changed files) and verify every occurrence is consistent in spelling and meaning.
     - **Spec delta title-identity check**: for every `### Requirement:` title under a `## MODIFIED Requirements` or `## REMOVED Requirements` section in a delta spec, and for the FROM title of every entry under `## RENAMED Requirements`, verify the same title exists byte-for-byte as a `### Requirement:` heading in the corresponding master spec `openspec/specs/<capability>/spec.md`. Skip capabilities whose master spec does not exist. A missing title is a self-check failure: copy the title verbatim from the master spec and fix the delta before spawning reviewers, because `"$cash_cli" archive` fails closed with `requirement_identity_mismatch` for non-matching titles.
     - **Signal-derived checks**:
       1. For EVERY `open` signal whose frontmatter contains a `check` field, execute the `check` value from the project root by passing it as the single command-string argument to `sh -c`, without applying relevance filtering. Executing a `check` command MUST NOT modify any file. Exit `0` means the check passed. Exit `1` means the anti-pattern is present: inspect any project-root-relative paths printed by the `check` command and compare them with this change's artifacts and, for cash-apply, changed files. If at least one printed path is in that artifact/source file set, treat the failure as in scope. If the `check` command prints no usable project-root-relative path, or the output cannot be reliably mapped to a project-root-relative path, fail closed and treat the detected instance as in scope unless the already-read repository state proves the instance is pre-existing or the required fix location is outside the structured scope declarations. If the detected instance is in scope and the fix location is not a protected grader path that is not covered by the structured-scope exception, fix it before spawning reviewers. If the detected instance is pre-existing, or its fix lies outside this change's structured scope declarations, or its fix lies inside a protected grader path that is not covered by the structured-scope exception, do not fix it, record one `範圍外 check 失敗` note in that round file's `## Fix Actions`, include the failing check result in the reviewers' context, and proceed to spawn reviewers. Any other exit code is an execution error: fall back to the existing best-effort judgment for that signal and record one fallback note in `## Fix Actions`. These note lines coexist with `None; pass condition met.` and do not count toward ledger `fixed_files`.
       2. For `open` signals without a `check` field, or signals whose `check` execution fell back because of an execution error, keep the existing best-effort behavior: if any relevant signal (see "Signals in reviewer context" below) describes a machine-checkable anti-pattern, run a corresponding check for it.
   - Fix every failure before spawning the reviewers. When the self-check runs after a round's fix actions, record what it caught and fixed in that round's `## Fix Actions`; self-check results are NOT reviewer findings and never feed the round decision.

   **Graded convergence and micro-verification round**
   - Run max 6 rounds per loop run.
   - The first round of each loop run MUST be a full round. When a round ends with `decision: next_round`, derive the next round type from its position within the current run: the next round MUST be `full` if and only if it is the fourth round of the current run; otherwise it MUST be `micro`.
   - Consecutive micro rounds are valid. Micro rounds count toward the 6-round cap. Fix actions that modify behavior or a design statement do not change the position-derived round type; the fourth-round checkpoint is the only full re-scan after the run's first round.
   - Except in an unseeded run's first round, every reviewer finding classified `Critical` or `Warning` MUST include `disposition`: one of `unresolved-prior`, `fix-introduced`, or `new`.
     - `unresolved-prior`: the finding matches a blocking finding from any prior round of this loop, including a bucket-1 seed from a prior run. A re-report is evidence that any recorded fix was ineffective.
     - `fix-introduced`: the finding cites one or more recorded fix actions that introduced the defect. Reviewer V and cash-propose reviewers MUST include the fix-action reference; cash-apply Reviewer B also follows the `introduced_by` rule below.
     - `new`: the finding matches no prior blocking finding. A finding that matches only a prior non-blocking triage note remains `new`; record only a one-line cross-reference to the original triage note, not a duplicate triage note or signal.
   - Disposition matching uses the same artifact or file and the same defect mechanism; line ranges are advisory. If deduplicated findings disagree, a blocking disposition (`unresolved-prior` or `fix-introduced`) wins over `new`.
   - Before accepting a `new` tag, the main agent MUST inspect whether the finding is at a fix-touched location from this loop or, for a seeded re-run, the prior run. If the defect stems from those fix actions, correct it to `fix-introduced` and record the original tag, corrected tag, and evidence in `## Fix Actions`. Record every disposition correction; list blocking-to-non-blocking corrections in the completion output.
   - A surviving `Critical` or `Warning` finding is blocking if and only if its verified disposition is `unresolved-prior` or `fix-introduced`. In a run's first round, every surviving `Critical` and `Warning` is blocking; a seeded re-run's first round instead uses the seeded cumulative blocking set.
   - A finding whose latest state is a non-blocking triage note MUST NOT become blocking again merely because it is re-reported. The only exception is new evidence tying it to recorded fix actions, which returns it as `fix-introduced` with a traced correction.
   - Every surviving `new` finding is non-blocking. Record it as a triage note in `## Fix Actions`, include it in the signals write step, and list it prominently in the completion output. For a non-blocking `Critical`, also recommend a follow-up change proposal.
   - Maintain a cumulative blocking set across the run. Every blocking finding enters the set in the round it is found. A member remains in the set even when a reviewer does not re-report it and leaves only through:
     1. verified resolution — a fix is recorded and a later reviewer confirms the fixed location is resolved without re-reporting the finding; or
     2. accepted risk — the member matches a user-consented accepted-risks entry.
   - Reviewer V, both fourth-round checkpoint reviewers, and both seeded re-run first-round reviewers MUST return an explicit resolved/unresolved verdict per member. If checkpoint reviewers disagree, any `unresolved` verdict keeps the member in the set. Record every verified-resolution removal with the member, fix reference, and verifying reviewer. Record every accepted-risk removal with the member and accepted-risk reference as a downgrade trace.
   - If all members are withheld under grader protection and no consented accepted-risk exit is obtainable, stop before spawning another reviewer and end with `decision: aborted` plus Abort triage. If this becomes true during the fix phase, override the pending `next_round` decision with `aborted` in the current not-yet-finalized round file.
   - Round files for completed rounds are immutable during an active loop; completed round files are immutable gate inputs. Write fix records, triage notes, downgrade traces, and corrections only in the round where they occur.
   - Except in an unseeded run's first round, pass if and only if the post-filter cumulative blocking set contains no blocking `Critical` and no blocking `Warning`. Non-blocking findings do not cause `next_round`.
   - If the sixth round does not pass, record `decision: aborted`, perform Abort triage, and end the workflow.

   **Fresh sub-agent calls**
   - Full rounds occur only at the run's first round and, when still needed, its fourth-round checkpoint. Each full round MUST spawn exactly TWO fresh reviewer sub-agents in parallel in one message:
     - **Reviewer A — Adherence**: checks that the artifacts (and for cash-apply, the implementation diff) match the prior artifacts. For cash-propose: proposal ↔ design ↔ spec ↔ tasks internal consistency, scope coverage, and acceptance criteria completeness. For cash-apply: implementation matches `design.md` Implementation Contract, `tasks.md` task descriptions, and `spec.md` requirements; `implementation-notes.md` deviations are justified.
     - **Reviewer B — Quality**: scans for bugs, regressions, missing tests, security sharp edges, and risks NOT directly named in the artifacts. For cash-propose: missing risks, unstated assumptions, scope gaps. For cash-apply: logic bugs, error-handling gaps at real boundaries, untested edge cases from spec `##### Example:` blocks.
   - Each micro round MUST spawn exactly ONE fresh sub-agent:
     - **Reviewer V — Verification**: performs delta verification against the cumulative blocking set and recorded fixes. Reviewer V MUST return an explicit resolved/unresolved verdict per member, check fix propagation, and report defects introduced by fixes.
   - A pre-spawn short-circuit round uses `round_type: full` and spawns no reviewer; this is the explicit exception for a seeded re-run where all members are withheld under grader protection and no consented exit exists.
   - Full-round reviewers receive identical context and return findings independently. Do not pass Reviewer A output into Reviewer B or vice versa.
   - Every reviewer after the run's first round receives every prior round file, the current cumulative blocking set, the artifact paths, the changed-file list for cash-apply, accepted-risks.md when present, and relevant `open` signals. In a seeded re-run, include prior-run round files too.
   - **Round context extract fallback**: when every prior round file cannot fit practical context, provide one extract per round containing all surviving findings and the complete `## Fix Actions`; record in the current round's `## Fix Actions` which rounds used extracts.
   - **Signals in reviewer context**: before spawning a round's reviewer(s), read `openspec/signals/` entries whose frontmatter `status` is `open`, select relevant issue classes, and include them in every reviewer context. This is read-only; continue silently when none exist.
   - **Run-first-round claim verification (Reviewer A)**: in the first round of every run, including a re-run, Reviewer A MUST verify code-facing claims in `design.md` against actual call sites and code before its other checks. A claim that does not hold is a finding.
   - After reviewers complete, aggregate findings by `location + summary`. When full-round reviewers independently raise the same finding with different `layer` values, the merged finding MUST take `layer == design`; when they disagree on a seeded member's verdict, any `unresolved` verdict wins.
   - Reviewer roles are independent calls. Do not perform review inline, reuse a reviewer, or invoke a scoring sub-agent.

   **Accepted-risks ledger**
   - The optional ledger path is `openspec/changes/<change>/reviews/accepted-risks.md`.
   - Every entry records `severity`, `location`, defect mechanism, acceptance rationale, and date.
   - Create, modify, or delete an entry only after explicit user consent in the current session. The loop MUST NOT edit this gate input as a fix action. If interaction is unavailable, do not write the entry and keep the finding surviving. A write failure prints a warning and does not fail the workflow.
   - When the file exists, include it in every reviewer context and re-evaluate both findings and cumulative-set members against it every round.
   - A finding that matches the same artifact or file and the same defect mechanism MUST be reduced to confidence ≤ 25; line ranges are advisory. The same subsystem alone MUST NOT trigger the downgrade.
   - Record every accepted-risks downgrade in `## Fix Actions`, naming the finding and matched entry, and list all such downgrades in the completion output.

   **Reviewer output requirements**
   - All reviewers classify findings as Critical, Warning, or Suggestion.
   - Every finding includes:
     - `severity`: `Critical`, `Warning`, or `Suggestion`
     - `confidence`: integer `0`–`100`
     - `layer`: `design` or `text`
     - `location`: artifact + section, or file path + line range
     - `summary`: one-line issue description
     - `recommendation`: concrete resolution
     - `disposition`: `unresolved-prior`, `fix-introduced`, or `new` after the run's first round, and in a seeded re-run's first round
   - Every `fix-introduced` finding MUST include `introduced_by`, citing one or more recorded fix actions that introduced the defect.
   - Classify a finding as `text` only for synchronization-only wording, count, spelling, or identifier consistency that changes no behavior or design statement. Otherwise use `design`. When a reviewer cannot decide between `design` and `text`, it MUST classify the finding as `design`.
   - **cash-apply introduced-by evidence**: in cash-apply, every Reviewer B `Critical` or `Warning` finding MUST include `introduced_by`, citing a concrete change-diff location, one or more fix-action records, or all fix actions from a named round when their interaction caused the regression. This rule does not apply to cash-propose.
   - Every finding names the artifact, section, source path, or changed file it applies to. Proposal-level scope errors may abort instead of entering fixes.

   **Confidence scoring rubric (per finding)**
   - `0` — Not confident at all. False positive or pre-existing issue. SHOULD NOT be reported.
   - `25` — Somewhat confident. Could be real but was not verified.
   - `50` — Moderately confident. Verified but minor, unlikely, or outside changed scope.
   - `75` — Highly confident. Verified and likely to occur, without direct artifact proof.
   - `100` — Certain. Direct evidence or a cited `SHALL`, Implementation Contract item, task line, or proposal non-goal proves the violation.
   - Direct artifact-requirement violations MUST score `100`, except the accepted-risks and cash-apply introduced-by downgrades below take precedence.

   **Confidence filter (applied by main agent before the decision)**
   - Re-check every `text` finding; if its fix can affect behavior or design, reclassify it to `design`. The main agent MUST NOT reclassify a `design` finding to `text`.
   - For an accepted-risks match, set confidence ≤ 25 and record the downgrade trace.
   - In cash-apply, a Reviewer B `Critical` or `Warning` finding without verifiable `introduced_by` evidence MUST be reduced to confidence ≤ 25. Record the finding and unverifiable reason in `## Fix Actions`, and list every such downgrade in the completion output.
   - Drop findings with `confidence < 50`; their required downgrade traces remain in `## Fix Actions`.
   - Downgrade findings with `confidence ∈ [50, 80)` to `Suggestion`.
   - Only findings with `confidence ≥ 80` remain `Critical` or `Warning`.
   - Verify each disposition after filtering, then update the cumulative blocking set. Only that set feeds the decision after the first round.
   - `critical_gap` is `true` if and only if the post-filter cumulative blocking set contains a `Critical`; the first round uses its surviving Criticals unless it is seeded.

   **Common false positives — do NOT flag**
   The following SHOULD NOT be reported, or if reported MUST be scored ≤ 25:
   - Pre-existing issues on lines not modified by this change (cash-apply) or content not introduced by this proposal (cash-propose).
   - Issues a linter, typechecker, formatter, or compiler would catch (missing imports, type errors, formatting, broken syntax). CI will fail separately; the review loop is not the right channel.
   - Pedantic style nitpicks that a senior engineer would not call out in review.
   - "Missing test coverage" complaints unless `tasks.md` or `design.md` explicitly required the test, or a spec `##### Example:` block is not exercised.
   - Issues already documented as intentional in `design.md`, `implementation-notes.md`, the proposal's Non-Goals section, or `## Alternatives Considered`.
   - Intentional behavior changes that align with the proposal's `## What Changes` or `## Proposed Solution`.
   - Suggestions to add abstractions, configurability, or defensive error handling that the spec/contract did not require — these conflict with Focused Implementation Discipline.
   - Suggestions to refactor unrelated code touched only incidentally — these conflict with Focused Implementation Discipline.

   **Failure handling**
   - If a reviewer returns no response or malformed output, retry once with a fresh sub-agent invocation for the reviewer role.
   - If both full-round parallel reviewers fail in the same round, treat it as a single role failure (the reviewer role); retry once.
   - If the same role fails two consecutive times in a single round, abort the entire cash workflow.
   - On abort from sub-agent failure, write the current round file with `decision: aborted` and include the failure note in `## Decision`.
   - Do not mark a malformed or failed round as passed, and do not continue to the next round after two consecutive failures.

   **Decision record requirements**
   - Record the post-filter cumulative blocking set's Critical count and Warning count. In an unseeded run's first round, use all surviving Critical and Warning findings because all are blocking.
   - Record the non-blocking triaged finding count.
   - Record `critical_gap` as `true` or `false`; it is `true` only when the post-filter cumulative blocking set contains a Critical.
   - The main agent records `round_type` as exactly `full` or `micro`.
   - The main agent records one concise rationale paragraph explaining why the round is `passed`, `next_round`, or `aborted`.
   - The decision follows only from the post-filter cumulative blocking set; do not pass a round that retains a blocking Critical or blocking Warning. Non-blocking findings are triaged and do not block pass.

   **Round file path**
   - Create the reviews directory if needed: `openspec/changes/<change>/reviews/`.
   - For `cash-propose`, write `openspec/changes/<change>/reviews/propose-r<N>.md`.
   - For `cash-apply`, write `openspec/changes/<change>/reviews/apply-r<N>.md`.
   - On a first run, use `<N>` as the 1-based round number. On a re-run after abort, continue numbering after the highest existing round file for that skill; never overwrite a completed round file.
   - The generic path pattern is `openspec/changes/<change>/reviews/<skill>-r<N>.md`.

   **Round file schema**
   - `# Cash Propose Review — Round <N>` or `# Cash Apply Review — Round <N>`
   - `## Reviewer Findings` — list aggregated, post-filter findings grouped under Critical / Warning / Suggestion. Each entry includes `severity`, `confidence`, `layer`, `location`, `summary`, `recommendation`, reviewer source, and where required `disposition` and `introduced_by`.
   - `## Rating` — post-filter cumulative blocking set Critical count, post-filter cumulative blocking set Warning count, non-blocking triaged finding count, `critical_gap`, `round_type`, and rationale.
   - `## Fix Actions`
   - `## Decision` — value MUST be exactly one of `passed`, `next_round`, or `aborted`.

   **Fix actions**
   - If the decision is `next_round`, address every surviving finding and every cumulative-set carryover before spawning the next round.
   - **Fix propagation**: fixes are the primary source of new defects. For EVERY concept a fix touches (an identifier, a count, a heading, a rule), grep that concept across ALL artifacts (and for cash-apply, the changed files) and synchronize every occurrence in the same fix pass — never fix only the flagged location.
   - After completing all fix actions, re-run the pre-round mechanical self-check and fix any failures before spawning the next round's reviewers.
   - Record modified files and the reason for each fix in `## Fix Actions`.
   - Re-run relevant CLI checks or tests before the next round when fixes affect generated artifacts or implementation code.
   - For `cash-propose`, if any fix action modifies proposal, design, tasks, or spec artifacts, run `"$cash_cli" validate "<name>"` again and fix validation errors before starting the next round.
   - 在每輪 fix actions 完成後，record the files that round's Fix Actions modified outside the change directory。若修改了 `.cash-skills/` 下的 runtime 檔，先在 project root 執行 `./install-cash-skills.fish --self`；rebuild the receipt before the next cash command。將候選路徑轉為 project-root-relative，濾除所有 `openspec/changes/` 下的路徑；若濾除後為空，不呼叫 Cash CLI 且不產生警告。否則先執行 `"$cash_cli" touched ensure "<change-name>"`，再以所有候選路徑執行 `"$cash_cli" touched record "<change-name>" --path <path>`；整批失敗時逐路徑重試，以記錄最大合法子集。`touched ensure` 或 `touched record` 失敗時印出警告並繼續，不使 workflow 失敗，也不改變任何 round file 的 `decision`；警告須列出未能記錄的路徑與 `error.code`，並 carry this warning into the final completion output。
   - If no fixes are needed because the round passed, write `None; pass condition met.`
   - **Fix-loop design circuit breaker**: cash-apply only. If resolving a surviving finding requires a synchronization primitive, identity/generation type, or state machine not defined in `design.md`, do not implement it. Record a `needs-design` note naming the finding, required mechanism, and reason; set `decision: aborted`; run Abort triage; and direct the user to `$cash-ingest`. In cash-propose, defining the mechanism in its own `design.md` is a normal fix and does not trigger this rule.
   - **Review round action obligation**: before a `next_round`, every surviving finding and every cumulative-set member counted in the decision MUST have an action in the current `## Fix Actions`.
     - A blocking finding/member MUST have exactly one of these three blocking actions: a fix naming modified files, a grader-protection note, or a user-consented accepted-risks entry. A triage note is not a valid action for a blocking member.
     - A non-blocking `new` finding uses its triage note. A re-report of a prior triage finding uses a one-line cross-reference to the original note and creates no duplicate signal.
     - A `needs-design` note forces `aborted` and cannot coexist with `next_round`.
     - Do not spawn the next reviewer while any required action is missing.

   **Abort triage**
   - When aborting because of the round cap, the design circuit breaker, or a fully grader-protected short-circuit, classify every unresolved finding into exactly one bucket and record the same triage in the final round's `## Fix Actions` and completion output:
     - bucket 1 — remains this change's obligation: every cumulative blocking set member not accepted with consent. It seeds a later re-run.
     - bucket 2 — a newly discovered issue that was never blocking: write it through the signals step; for Critical, recommend a follow-up change proposal. Never place a previously blocking finding here.
     - bucket 3 — accepted trade-off: write it to accepted-risks.md only with explicit consent. Without consent, move it to bucket 1 and note that accepted-risks recording awaits consent.
   - Do not recommend re-running unchanged. State the concrete prerequisite: fix bucket 1, obtain bucket-3 consent, or update design/scope.
   - A re-run MUST continue numbering after the highest existing round file, include every prior round file or the extract fallback, seed the cumulative blocking set from the prior run's bucket-1 findings, and apply the cumulative-set pass condition in its first full round. Its first-round reviewers return an explicit resolved/unresolved verdict per member.
   - The 6-round cap and round type use positions within the new run, independent of global round-file numbers.
   - If a seeded re-run starts while all members are withheld under grader protection and no consented exit exists, short-circuit before reviewers: write one continued-number round file with no reviewer findings, `round_type: full`, `decision: aborted`, and triage; append one ledger row. The pre-spawn short-circuit round uses `round_type: full` and spawns no reviewer. The completion output MUST direct the user to obtain consent for the protected members or expand the structured scope declarations via `$cash-ingest` before any further re-run.
   - Consecutive sub-agent failure aborts and proposal-level scope-error aborts are exempt from this triage.

   <!-- GRADER-IMMUTABILITY -->
   **Grader immutability**
   - During an active cash review loop, the main agent MUST NOT modify, whether as a fix action or as a mechanical self-check fix, any file in this protected grader path set unless that file is explicitly named in the current change's proposal `## Impact` section or in its `tasks.md`:
     - `.claude/skills/cash-propose/SKILL.md`
     - `.claude/skills/cash-apply/SKILL.md`
     - `.agents/skills/cash-propose/SKILL.md`
     - `.agents/skills/cash-apply/SKILL.md`
     - `.cash.yaml`
     - `scripts/cash-skills/tests/skill-checks.fish`
     - `scripts/cash-cli/tests/cli-checks.fish`
     - `openspec/specs/`
   - **Structured scope declarations**: A file counts as explicitly named only when its project-root-relative path appears in a structured scope declaration: an affected-code entry in proposal `## Impact`, or a `tasks.md` path that is explicitly identified as a delivery target. A path that appears only in a verification command, a rule description, an example, a review finding, reviewer context, or other incidental prose MUST NOT count as a structured scope declaration. Naming a directory path in a structured scope declaration names every file under it.
   - A loop already in progress continues under the instruction version it started with; regenerated instructions take effect only from the next loop run.
   - The main agent MUST NOT add, modify, or remove the `check` frontmatter field of any signal under `openspec/signals/`, regardless of declared scope. The `check` field is grader input for the pre-round mechanical self-check.
   - If fixing a surviving finding would require modifying a protected file outside the structured scope declarations, or touching any signal's `check` field, do not make that modification. Record `未修復：裁判面保護` (an unfixed-due-to-grader-protection note) in `## Fix Actions`, naming the protected file and finding. The finding remains surviving for the round decision. This is the explicit exception to the obligations to fix Critical/Warning findings before the next round in the `cash-propose 品質關卡` and `cash-apply 品質關卡` requirements: fixes are required except any finding withheld under the grader-immutability rule.
   - A protected file modified under the declared-scope exception does not alter the position-derived next round type. If the loop reaches round 6 without passing because protected findings remain, write `decision: aborted` under the existing round-limit rule.
   - The cash workflow completion output MUST list every `未修復：裁判面保護` record from every round, even if a later round passes: for `cash-propose` with `decision: passed`, list the records in the final summary; for `cash-apply` with `decision: passed`, list the records in the gate-complete final response; for any `decision: aborted`, list the records in the unresolved-findings warning.

   <!-- LOOP-LEDGER-STEP -->
   **Loop ledger step**
   - After each round file is finalized, append exactly one row to `openspec/changes/<change>/reviews/loop-ledger.tsv`. For a `next_round` round, append immediately before spawning the next round's reviewers, after all fix actions, post-fix self-check records, and validation re-run fix records have been written. For a final `passed` or `aborted` round, append at loop end before the signals write step.
   - If `loop-ledger.tsv` does not exist, create it first with this exact tab-separated header row: `skill	round	round_type	criticals	warnings	decision	fixed_files`.
   - Append data rows with exactly seven tab-separated fields in this order:
     - `skill`: `propose` or `apply`
     - `round`: 1-based round number
     - `round_type`: `full` or `micro`
     - `criticals`: post-filter cumulative blocking set Critical count; in an unseeded first round, all surviving Criticals; `0` when empty, including failure-aborted rounds
     - `warnings`: post-filter cumulative blocking set Warning count; in an unseeded first round, all surviving Warnings; `0` when empty, including failure-aborted rounds
     - `decision`: `passed`, `next_round`, or `aborted`
     - `fixed_files`: number of distinct files recorded as modified in that round's `## Fix Actions`; use `0` when none are recorded, and do not count fallback, triage, downgrade-trace, disposition-correction, or grader-protection notes
   - The ledger is an append-only event log. Rows from propose loops, apply loops, and later re-runs after an abort accumulate chronologically in the same file. `(skill, round)` is not a unique key; duplicate round numbers from re-runs are valid.
   - Round files remain authoritative. If a round file and ledger disagree, trust the round file.
   - If writing the ledger fails, print a warning and continue the cash workflow unchanged.

   **Round file language**
   - The Round file (`openspec/changes/<change>/reviews/<skill>-r<N>.md`) prose content — Reviewer Findings, Rating rationale, Fix Actions descriptions, and the `## Decision` explanation — MUST be written in Traditional Chinese.
   - **Keep the following verbatim (do not translate):**
     - Section headings: `# Cash Propose Review — Round <N>`, `# Cash Apply Review — Round <N>`, `## Reviewer Findings`, `## Rating`, `## Fix Actions`, `## Decision`.
     - The `decision` value: one of `passed`, `next_round`, `aborted`.
     - Field names and their values: `critical_gap` (`true` / `false`), `round_type` (`full` / `micro`), `severity`, `confidence`, `layer` (`design` / `text`), `disposition` (`unresolved-prior` / `fix-introduced` / `new`), `introduced_by`, `location`, `summary`, `recommendation`.
     - Direct quotations from any source artifact, kept in the source's original language.
     - CLI commands, file paths, code identifiers, artifact IDs, capability slugs.
   - This rule applies to both `cash-propose` and `cash-apply` round files because they share this review-loop template.
   - If the user explicitly requests another language later, follow the latest user instruction.

   **Signals write step**

   <!-- SIGNALS-WRITE-STEP -->
   - **When it runs**: Run this step only after the review loop has ENDED — that is, the final round file's `decision` is `passed` or `aborted` — and the mechanical decision has already been recorded. This step MUST run only after that decision is recorded, and it MUST NOT change the `decision` of any round file. It applies to both `cash-propose` and `cash-apply`, since this template is shared.
   - **Target set**: The target set is every finding that, in ANY single round of THIS change's loop, survived the confidence filter classified as `Critical` or `Warning`. Cover findings from every round, not only the final round — a finding that was caught and fixed in an early round of an otherwise-passing loop still produces a signal. Deduplicate the target set by issue class, so an issue class seen across multiple rounds is processed exactly once. This issue-class deduplication is INDEPENDENT of any per-round `location + summary` aggregation deduplication used elsewhere in the loop. Findings classified `Suggestion`, and any finding with `confidence < 80`, MUST NOT produce a signal.
   - **Matching rubric**: For each deduplicated finding class, read the existing signals under `openspec/signals/` and judge issue-class match by: SAME capability or domain AND SAME underlying rule or anti-pattern. Differing free-text wording alone does NOT make a different class; a different root cause DOES make a different class. When uncertain, PREFER creating a new signal over merging into an existing one.
   - **On match to an existing `open` signal**: Reuse that signal's slug and update it in place — increment `occurrences`, update `last_seen` to today (`YYYY-MM-DD`), append one `## Occurrences` entry (date, change name, source skill + round, and a one-line context), and append the source round file path to `links`. Do NOT change its `status`. Do NOT add, modify, or remove its `check` field; preserve any existing human-authored `check` byte-for-byte.
   - **On no `open` match** (including when only an `addressed` or `dismissed` signal matches): Create a NEW signal. Before coining the `<slug>`, list the existing `openspec/signals/*.md` files and choose a `<slug>` that does NOT already exist. The slug is a short semantic ASCII kebab-case issue-class identifier matching `^[a-z0-9]+(-[a-z0-9]+)*$` (e.g. `spec-requirement-no-backing-task`); it is NOT a mechanical transform of `location + summary`. If the natural slug is already taken, disambiguate with a suffix. Creating a signal MUST NOT overwrite any existing signal file and MUST NOT change any existing signal's human-maintained `status`. The new signal has `status: open`, `occurrences: 1`, and `first_seen` = `last_seen` = today.
   - **Signal file schema**: Each signal file has frontmatter with `id` (= slug), `type` (default `recurring-finding` for review-loop-written signals), `status`, `occurrences`, `first_seen`, `last_seen`, `links`, and optional human-authored `check`; followed by a title, a description paragraph, and a `## Occurrences` section. New signals created by this step MUST NOT contain an automatically authored `check`.
   - 寫入 signals 後，record every signal file this step created or updated。將路徑轉為 project-root-relative，濾除所有 `openspec/changes/` 下的路徑；若濾除後為空，不呼叫 Cash CLI 且不產生警告。否則先執行 `"$cash_cli" touched ensure "<change-name>"`，再以所有候選路徑執行 `"$cash_cli" touched record "<change-name>" --path <path>`；整批失敗時逐路徑重試，以記錄最大合法子集。`touched ensure` 或 `touched record` 失敗時印出警告並繼續，不使 workflow 失敗，也不改變任何 round file 的 `decision`；警告須列出未能記錄的路徑與 `error.code`，並 carry this warning into the final completion output。
   - **Failure handling**: If writing under `openspec/signals/` fails, print a warning but do NOT fail the cash workflow — signals are an auxiliary layer. If there are no qualifying findings, write nothing.

**Output During Implementation**

```
## Implementing: <change-name> (schema: <schema-name>)

Working on task 3/7: <task description>
[...implementation happening...]
✓ Task complete

Working on task 4/7: <task description>
[...implementation happening...]
✓ Task complete
```

**Output On Completion**

```
## Implementation Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Progress:** 7/7 tasks complete ✓

### Completed This Session
- [x] Task 1
- [x] Task 2
...

All tasks complete. The cash quality gate runs next; archive guidance is shown only if it passes.
```

**Output On Pause (Issue Encountered)**

```
## Implementation Paused

**Change:** <change-name>
**Schema:** <schema-name>
**Progress:** 4/7 tasks complete

### Issue Encountered
<description of the issue>

**Options:**
1. <option 1>
2. <option 2>
3. Other approach

What would you like to do?
```

**Fluid Workflow Integration**

This skill supports the "actions on a change" model:

- **Can be invoked anytime**: Before all artifacts are done (if tasks exist), after partial implementation, interleaved with other actions
- **Allows artifact updates**: If implementation reveals design issues, suggest updating artifacts - not phase-locked, work fluidly
