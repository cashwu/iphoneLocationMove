---
name: cash-propose
description: Create a Cash change proposal with sub-agent quality gates
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

Create a complete Cash change proposal — from requirement to validated artifacts — in a single workflow.

**Input**: The argument after `/cash-propose` is the requirement description. Examples:

- `/cash-propose add dark mode`
- `/cash-propose fix the login page crash`
- `/cash-propose improve search performance`

If no argument is provided, the workflow will extract requirements from conversation context or ask.

**Prerequisites**: The project-local launcher initialized above is required. If root resolution, launcher validation, or a Cash command fails, report the exact error and STOP.

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

**Steps**

1. **Determine the requirement source**

   a. **Argument provided** (e.g., "add dark mode") → use it as the requirement description, skip to deriving the change name below.

   b. **Plan file available**:
   - Check if the conversation context mentions a plan file path (plan mode system messages include the path like `~/.claude/plans/<name>.md`)
   - If found, check if the file exists at `~/.claude/plans/`
   - If a plan file is found, use the **AskUserQuestion tool** to ask:
     - Option 1: Use the plan file
     - Option 2: Use conversation context
   - If conversation context has no relevant discussion, mention this when presenting the choice
   - If the user picks the plan file → read it and extract:
     - `plan_title` (H1 heading) → use as requirement description
     - `plan_context` (Context section) → use as proposal Why/Motivation content
     - `plan_stages` (numbered implementation stages) → use for artifact creation
     - `plan_files` (all file paths mentioned) → use for Impact section
   - If the user picks conversation context → fall through to (c)

   c. **Conversation context** → attempt to extract requirements from conversation history
   - If context is insufficient, use the **AskUserQuestion tool** to ask what they want to build

   From the resolved description, derive a kebab-case change name (e.g., "add dark mode" → `add-dark-mode`).
   Do not keep archive-style date prefixes in active change names. If the source name starts with `YYYY-MM-DD-`, strip that date prefix before running `"$cash_cli" new change`; archived change names and directories are historical references, not active names to reuse.

   **IMPORTANT**: Do NOT proceed without understanding what the user wants to build.

2. **Classify the change type**

   Based on the requirement, classify the change into one of three types:

   | Type     | When to use                                                         |
   | -------- | ------------------------------------------------------------------- |
   | Feature  | New functionality, new capabilities                                 |
   | Bug Fix  | Fixing existing behavior, resolving errors                          |
   | Refactor | Architecture improvements, performance optimization, UI adjustments |

   This determines the narrative emphasis in `## Motivation` and `## Proposed Solution`.

3. **Scan existing specs for relevance**

   Before creating the change, check if any existing specs overlap:
   1. Use the **Glob tool** to list all files matching `openspec/specs/*/spec.md`
   2. Extract directory names as the spec identifier list
   3. Compare against the user's description to identify related specs (max 5 candidates)
   4. For each candidate (max 3), read the first 10 lines to retrieve the Purpose section
   5. If related specs are found, display them as an informational summary

   **IMPORTANT**:
   - If related specs are found, display them but do NOT stop or ask for confirmation — continue to the next step
   - If no related specs are found, silently proceed without mentioning the scan


3b. **Read open signals for prioritization (cash-propose only)**

<!-- SIGNALS-READ-STEP -->

   After scanning existing specs, read the signals under `openspec/signals/` whose frontmatter `status` is `open`, and use them to inform how you prioritize this change's scope. This step belongs to `cash-propose` only.

   - Read every signal file under `openspec/signals/` and keep only those whose frontmatter `status` is `open`. Selecting which `open` signals are relevant to the current requirement is best-effort agent judgment.
   - Surface the relevant `open` signals as an INFORMATIONAL prioritization summary — for example, which recurring issue classes or frictions might relate to this change — to help decide what to include in or exclude from scope.
   - This read is purely informational. It MUST NOT block the workflow, MUST NOT require user confirmation to continue, and MUST NOT modify, create, or delete any signal. Read signals only; never write them.
   - If `openspec/signals/` is absent or contains no `open` signal, continue SILENTLY without printing any summary.

4. **Create the change directory**

   ```bash
   "$cash_cli" new change "<name>" --agent claude
   ```

   If a change with that name already exists, suggest continuing the existing change instead of creating a new one.

5. **Write the proposal**

   **IMPORTANT — file path rules for the `## Impact` section:**
   - All file paths SHALL be written relative to the project root (e.g., `src/lib/foo.ts`, `src-tauri/crates/core/src/bar.rs`, `openspec/specs/auth/spec.md`).
   - Do NOT use relative fragments (e.g., `parser/mod.rs`, `core/mod.rs`) — preflight rejects them as non-anchored paths.
   - Do NOT wrap shell commands in backticks inside artifact text (e.g., `` `git mv a.rs b.rs` ``) — preflight's backtick extractor will otherwise mis-parse the command as a file reference.
   - When referring to a file without naming its concrete path, use descriptive prose (e.g., "Parser 入口檔") rather than a backticked path fragment.

   Get instructions:

   ```bash
   "$cash_cli" instructions proposal --change "<name>" --json
   ```

   Use the `template` returned by the CLI as the proposal structure. Fill in every section, using the change type to guide the narrative emphasis, then write the content via CLI:

   ```bash
   "$cash_cli" new artifact proposal --change "<name>" --stdin <<'ARTIFACT_EOF'
   <proposal content>
   ARTIFACT_EOF
   ```

   If the command fails with a validation error, fix the content and retry.

   **cash-propose impact granularity advisory**
   - After writing the proposal and before creating `design.md`, count the affected-code path entries under proposal `## Impact` across Modified, New, and Removed.
   - Exclude `(none)` placeholder lines. Count a directory entry as one entry, so the result is a lower bound.
   - When the affected-code path count exceeds 15, print an informational warning containing the count and recommend splitting the change by capability.
   - When the count is 15 or fewer, print nothing.
   - Treat 15 entries as silent and 16 entries as advisory.
   - This advisory MUST NOT block the workflow or require user confirmation.

6. **Get the artifact build order**

   ```bash
   "$cash_cli" status --change "<name>" --json
   ```

   Parse the JSON to get:
   - `applyRequires`: array of artifact IDs needed before implementation
   - `artifacts`: list of all artifacts with their status and dependencies

7. **Create remaining artifacts in sequence**

   Loop through artifacts in dependency order (skip proposal since it's already done):

   a. **For each artifact that is `ready` (dependencies satisfied)**:
   - **Check if the artifact is optional**: If the artifact is NOT in the dependency chain of any `applyRequires` artifact (i.e., removing it would not block reaching apply), it is optional. Get its instructions and read the `instruction` field. If the instruction contains conditional criteria (e.g., "create only if any apply"), evaluate whether any criteria apply to this change based on the proposal content. If none apply, skip the artifact and show: "⊘ Skipped <artifact-id> (not needed for this change)". Then continue to the next artifact.
   - Get instructions:
     ```bash
     "$cash_cli" instructions <artifact-id> --change "<name>" --json
     ```
   - The instructions JSON includes:
     - `context`: Project background (constraints for you - do NOT include in output)
     - `rules`: Artifact-specific rules (constraints for you - do NOT include in output)
     - `template`: The structure to use for your output file
     - `instruction`: Schema-specific guidance
     - `outputPath`: Where to write the artifact
     - `dependencies`: Completed artifacts to read for context
     - `locale`: The language to write the artifact in (e.g., "Japanese (日本語)"). If present, you MUST write the artifact content in this language. For spec files (specs/\*_/_.md), the Spec-file language policy below takes precedence over `locale`.
   - Read any completed dependency files for context
   - Generate the artifact content using `template` as the structure
   - Apply `context` and `rules` as constraints - but do NOT copy them into the file
   - Write the artifact via CLI (the CLI handles directory creation and format validation):

     For **design** or **tasks**:

     ```bash
     "$cash_cli" new artifact <artifact-id> --change "<name>" --stdin <<'ARTIFACT_EOF'
     <content>
     ARTIFACT_EOF
     ```

     For **specs** (one command per capability):

     ```bash
     "$cash_cli" new artifact spec <capability-name> --change "<name>" --stdin <<'ARTIFACT_EOF'
     <delta spec content>
     ARTIFACT_EOF
     ```

     If the command fails with a validation error, fix the content and retry.

   - Show brief progress: "✓ Created <artifact-id>"

   b. **Continue until all `applyRequires` artifacts are complete**
   - After creating each artifact, re-run `"$cash_cli" status --change "<name>" --json`
   - Check if every artifact ID in `applyRequires` has `status: "done"`
   - Stop when all `applyRequires` artifacts are done

   c. **If an artifact requires user input** (unclear context):
   - Use **AskUserQuestion tool** to clarify
   - Then continue with creation


   **Artifact language for cash-propose**

   All change artifacts produced by `cash-propose` (`proposal.md`, `design.md`, `tasks.md`, and any other non-spec artifact under `openspec/changes/<change>/`) MUST be written in Traditional Chinese, regardless of whether the CLI provides a `locale` field.

   This applies to artifacts generated in step 5 (proposal) and step 7 (remaining artifacts), and to any artifacts modified during the review loop fix actions.

   **Spec-file language policy (delta and master specs):**

   - `openspec/changes/<change>/specs/<capability>/spec.md` (delta spec)
   - `openspec/specs/<capability>/spec.md` (master spec)

   Spec files are written in Traditional Chinese prose with English structural keywords. Keep the following verbatim in English: `## ADDED Requirements`, `## MODIFIED Requirements`, `## REMOVED Requirements`, `## RENAMED Requirements`, `### Requirement:`, `#### Scenario:`, `##### Example:`, and the **GIVEN** / **WHEN** / **THEN** / **AND** step markers. Normative verbs (SHALL / MUST / SHOULD / MAY and their NOT forms) stay in English embedded inside Chinese sentences. Code identifiers, file paths, CLI commands, schema field names, and quoted source text stay verbatim. Requirement titles are written in Chinese; every title under `## MODIFIED Requirements` or `## REMOVED Requirements`, and the FROM title of every `## RENAMED Requirements` entry, MUST be copied byte-for-byte from the current master spec — never retyped, reworded, or translated — because `"$cash_cli" archive` matches requirement titles verbatim and fails closed with `requirement_identity_mismatch` when a title does not match. Historical spec files under `openspec/changes/archive/` are historical records and are not retroactively translated.

   **Keep the following verbatim (do not translate) even inside Chinese prose:**

   - Shell commands and CLI flags
   - File paths (absolute or repo-relative)
   - Code identifiers (function names, variable names, type names)
   - Schema field names (e.g., `applyRequires`, `outputPath`, `dependencies`)
   - Artifact IDs and capability slugs
   - Quoted source text from existing artifacts

   If the user explicitly requests another language later, follow the latest user instruction.

   The goal is predictable Chinese-facing artifacts for cash-propose while preserving exact technical references and keeping spec deltas compatible with master specs.

8. **Validation**

    ```bash
    "$cash_cli" validate "<name>"
    ```

    If validation fails, fix errors and re-validate.


9. **Sub-Agent Review/Rating/Fix Loop**

<!-- REVIEW-GATE:BEGIN -->
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
     - **Reviewer B — Quality**: scans for bugs, regressions, missing tests, security sharp edges, and risks NOT directly named in the artifacts. Its complexity lens covers `new dependency`, `single-implementation abstraction`, `pass-through wrapper`, `speculative configuration`, `duplicate existing capability`, and custom mechanisms that present a `stdlib`／`native` replacement opportunity.
       - For cash-propose: scan proposal, design, and tasks for complexity introduced or permitted by those artifacts without evidence that the contract requires it, in addition to missing risks, unstated assumptions, and scope gaps.
       - For cash-apply: scan only complexity introduced by the changed diff, in addition to logic bugs, error-handling gaps at real boundaries, and untested edge cases from spec `##### Example:` blocks.
       - Do not report this lens against pre-existing code, unrelated refactors, mechanisms explicitly required by the contract, or intentional complexity already justified in `design.md`, `implementation-notes.md`, proposal Non-Goals, or `## Alternatives Considered`.
       - LOC, estimated token use, cost, and time are not inputs to a finding, severity, confidence, or gate decision.
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
   - Intentional behavior changes that align with the proposal's `## Proposed Solution`.
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
   - **Fix-loop design circuit breaker**: cash-apply only. If resolving a surviving finding requires a synchronization primitive, identity/generation type, or state machine not defined in `design.md`, do not implement it. Record a `needs-design` note naming the finding, required mechanism, and reason; set `decision: aborted`; run Abort triage; and direct the user to `/cash-ingest`. In cash-propose, defining the mechanism in its own `design.md` is a normal fix and does not trigger this rule.
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
   - If a seeded re-run starts while all members are withheld under grader protection and no consented exit exists, short-circuit before reviewers: write one continued-number round file with no reviewer findings, `round_type: full`, `decision: aborted`, and triage; append one ledger row. The pre-spawn short-circuit round uses `round_type: full` and spawns no reviewer. The completion output MUST direct the user to obtain consent for the protected members or expand the structured scope declarations via `/cash-ingest` before any further re-run.
   - Consecutive sub-agent failure aborts and proposal-level scope-error aborts are exempt from this triage.

   <!-- GRADER-IMMUTABILITY -->
   **Grader immutability**
   - During an active cash review loop, the main agent MUST NOT modify, whether as a fix action or as a mechanical self-check fix, any file in this protected grader path set unless that file is explicitly named in the current change's proposal `## Impact` section or in its `tasks.md`:
     - `.claude/skills/cash-propose/SKILL.md`
     - `.claude/skills/cash-apply/SKILL.md`
     - `.agents/skills/cash-propose/SKILL.md`
     - `.agents/skills/cash-apply/SKILL.md`
     - `.cash.yaml`
     - `scripts/cash-skills/blocks/review-gate.md`
     - `scripts/cash-skills/generate.fish`
     - `scripts/cash-skills/variant-rules.yaml`
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
<!-- REVIEW-GATE:END -->

10. **Finish the cash proposal workflow**

    Show summary:
    - Change name and location
    - List of artifacts created
    - Validation result
    - Final cash review decision

    Do not move the change out of `openspec/changes/`.

    The cash proposal workflow ends with the active change still available for implementation.

    If the user wants to temporarily set the change aside, they can do that manually after this workflow ends.

    Inform the user:
    - The change remains active.
    - The cash quality gate has completed or aborted with a recorded round file.
    - The user can start implementation later with the `cash-apply` skill.

    If the current environment has a separate planning mode, also remind the user to switch the session to normal mode before running an apply workflow. This is only a reminder: do NOT try to switch modes with any tool, do NOT ask whether to switch modes, and do NOT invoke apply.

    The cash-propose workflow ENDS here.

    Do NOT invoke the `cash-apply` skill.

    Do NOT call **AskUserQuestion** to ask whether to apply.

    Do NOT invoke `"$cash_cli" park` or run any command that parks the change.

    This behavior is identical across Auto Mode, interactive mode, and any other agent mode.

    The end state is explicit: artifacts exist, validation has run, review records exist, and the change remains active.

**Artifact Creation Guidelines**

- Follow the `instruction` field from `"$cash_cli" instructions` for each artifact type
- Read dependency artifacts for context before creating new ones
- Use `template` as the structure for your output file - fill in its sections
- **IMPORTANT**: `context` and `rules` are constraints for YOU, not content for the file
  - Do NOT copy `<context>`, `<rules>`, `<project_context>` blocks into the artifact
  - These guide what you write, but should never appear in the output
- **Parallel task markers (`[P]`)**: When creating the **tasks** artifact, first read `.cash.yaml`. If `parallel_tasks: true` is set, add `[P]` markers to tasks that can be executed in parallel. Format: `- [ ] [P] Task description`. A task qualifies for `[P]` if it targets different files from other pending tasks AND has no dependency on incomplete tasks in the same group. When `parallel_tasks` is not enabled, do NOT add `[P]` markers.

**Guardrails**

- **NEVER** write application code or implement features during this workflow
- **NEVER** skip the artifact workflow to write code directly
- **NEVER** reinterpret requirements by ignoring the proposal file
- **NEVER** invoke the `cash-apply` skill — this workflow ends after artifact creation. The user decides when to start implementation
- If **AskUserQuestion tool** is not available, ask the same questions as plain text and wait for the user's response
