---
name: cash-commit
description: "Commit files related to a specific Cash change"
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

Commit files related to a specific Cash change.

This is a **utility skill** (not a workflow step). It reads source file tracking data and artifact changes to stage and commit only the files belonging to one change — useful when multiple changes are in progress simultaneously.

**Input**: Optionally specify a change name after `$cash-commit` (e.g., `$cash-commit add-auth`). If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

**Prerequisites**: This skill requires `git`. Run `git --version`. If git is not available (command not found or similar error), inform the user to install git and STOP.

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

**Steps**

1. **Select the change**

   If a name is provided, use it. Otherwise:
   - Infer from conversation context if the user mentioned a change
   - Auto-select if only one active change exists
   - If ambiguous, run `"$cash_cli" list --json` to get available changes. Use the **AskUserQuestion tool** to let the user select

   Always announce: "Committing for change: <name>"

2. **Read tracking file**

   Before building any source allowlist, run:

   ```bash
   "$cash_cli" touched ensure "<change-name>"
   ```

   If ensure fails, report the error and STOP. Then parse `.cash-skills/state/touched/<change-name>.json`; Cash state is the only allowlist authority after this point, except when step 2a establishes a post-archive recovery source. Do not re-read or merge legacy state.
   If ensure fails with `touched_invalid` naming a `task_desc` that no longer exists in `tasks.md`, determine whether that task was renamed or removed. If renamed, update that entry's `task_desc` in `.cash-skills/state/touched/<change-name>.json` to the task's current description, then re-run ensure. Editing `task_desc` to repair a rename is the one permitted manual edit to touched state; never delete the file. If removed, stop and run `$cash-ingest` with the current `touched_invalid` error and change name as conversation context so it selects the existing change and restores the exact `task_desc` as a completed `[x]` task in `tasks.md`, then re-run ensure; do not edit or delete the touched entry, because its `files` remain attributed to that historical task. If restoring the exact `task_desc` would cause a task label conflict, stop and use `$cash-ingest` with the same conversation context to resolve the artifact conflict; do not guess a new label or reattribute `files`.

   Expected format:

   ```json
   {
     "change": "<change-name>",
     "touched": [
       {
         "task_id": "1",
         "task_desc": "Task description",
         "files": ["src/file1.ts", "src/file2.ts"]
       }
     ]
   }
   ```

   Split the `touched` array into per-task entries and the reserved entry whose `task_id` is `review-loop`. Keep the reserved entry's files in a separate review-loop output set; they remain part of the commit set and MUST NOT be mixed into per-task attribution.

   The ensured file must exist and match the versioned Cash schema. An empty `files` array means there are no tracked source files, unless step 2a establishes a post-archive recovery source.

   **Resolve shared review-loop signals.** For every `openspec/signals/` path in the review-loop output set, read its frontmatter `links`. Mark the file shared only when a link points to `openspec/changes/<other>/reviews/`, `<other>` differs from `<change-name>`, and `openspec/changes/<other>/` or `openspec/changes/.parked/<other>/` exists now — only when that other change directory still exists. Historical links to archived changes do not make a file shared. For each shared file, use the **AskUserQuestion tool** to require an explicit whole-file include or whole-file exclude decision, and explain that a shared signal file cannot be split by change. Never silently include or silently exclude it. If excluded, move it to `### Unrelated Changes (not included)` with a `user-decision: excluded shared signal` note and remember to report that it remains dirty.

2a. **Detect a post-archive empty allowlist**

    An empty tracking file has two very different causes: the change genuinely tracked no source files, or archive already ran and deleted the Cash state that recorded them. Step 2 cannot tell them apart, because `touched ensure` recreates an empty shell when the file is missing. Evaluate all three of these conditions:

    1. The parsed files array is empty.
    2. Neither `openspec/changes/<change-name>/` nor `openspec/changes/.parked/<change-name>/` exists.
    3. At least one directory matching `openspec/changes/archive/<date>-<change-name>/` exists.

    If any condition is false, keep the existing behavior and continue to step 3 — an empty `files` array then genuinely means there are no tracked source files.

    If all three hold, the change was archived before this commit and the tracking file is a post-archive empty shell. Do NOT treat it as "no tracked source files".

    **Resolve the archive directory.** Different dates make several same-name archives legitimate, so disambiguate before asking. Keep only the candidates whose `archive-manifest.json` records a `change` equal to `<change-name>` and a `destination` equal to that directory's repo-relative path, then take the one with the newest date prefix. Only when no candidate passes validation, more than one survives it, or the manifest is absent or unparseable, report the ambiguity and use the **AskUserQuestion tool** to confirm which archive directory to use.

    **Resolve the source allowlist** from the resolved directory's `archive-manifest.json`:

    - If `touched_files` is present and non-empty, use it as the source allowlist for the rest of this workflow. Label the Source Files section with its archive-manifest origin and state that it is a point-in-time snapshot taken at archive time: files changed after archiving — during review-loop fix actions, for instance — were never recorded in it, so any dirty source file outside the list still appears under Unrelated Changes for the user to judge.
    - If `touched_files` is absent (an archive created before that field existed) or present but empty, print a warning naming the resolved archive directory and use the **AskUserQuestion tool** to choose the allowlist source. The options are: derive it from the affected-code paths in the archived `proposal.md` `## Impact` section, select the files manually, or stop without committing. Stopping without committing is a legitimate outcome. NEVER fall through to classifying every dirty source file as Unrelated without an explicit user choice.

    **Rebuild the change's file sets** for the remaining steps:

    - Artifact set: deletions under `openspec/changes/<change-name>/` plus additions or modifications under the resolved archive directory.
    - Spec sync set: only when the manifest records `specs_synced` as true, the `openspec/specs/` paths listed in its `master_digests` that are both dirty and whose current digest equals the value the manifest recorded for that path. The current digest is the sha256 hexdigest of the file's contents (`shasum -a 256 <path>`). A path whose digest differs belongs to someone else's edit: leave it in Unrelated Changes and say so. When `specs_synced` is false the manifest recorded pre-sync digests, so every `openspec/specs/` path stays in Unrelated Changes.

    All three sets — the artifact set, the resolved source allowlist, and the spec sync set — are part of the commit set, not display-only. Every dirty path in them is staged in step 8 unless the user removes it in step 6. The allowlist is a filter over dirty files, not a list of paths to stage blindly: `touched_files` is a snapshot, so it can name paths that are already clean or no longer exist.

    Apply the same shared review-loop signal rule from step 2 to every `openspec/signals/` path in the resolved source allowlist, including the same active-or-parked existence check and explicit whole-file include/exclude decision. Step 2a has no task-entry granularity, but that MUST NOT bypass the shared-file decision.

3. **Collect artifact files**

   Run `git status --porcelain` and filter the output to files under `openspec/changes/<name>/`. These are the change's artifact files (proposal, design, tasks, specs, etc.).

   When step 2a applies, use the artifact set it rebuilt instead of this filter.

4. **Identify unrelated dirty files**

   From the full `git status --porcelain` output, any dirty files NOT in the artifact set and NOT in the tracking file are "unrelated changes."

   As an explicit exception, a shared signal file excluded by the user's decision belongs in Unrelated Changes even though it remains in the tracking file. Preserve the `user-decision: excluded shared signal` note.

   When step 2a applies, "the tracking file" means the source allowlist step 2a resolved, and the exclusion also covers step 2a's artifact set and its spec sync set.

5. **Display commit plan**

   Show the file list grouped into sections:

   ```
   ## Commit Plan: <change-name>

   ### Change Artifacts
   - M  openspec/changes/<name>/proposal.md
   - M  openspec/changes/<name>/tasks.md

   ### Source Files
   **Task 1: <task description>**
   - M  src/lib/components/search.svelte
   - A  src/lib/stores/search.ts

   **Task 3: <task description>**
   - M  src/routes/+page.svelte

   ### Review Loop Outputs
   - M  openspec/signals/example.md

   ### Unrelated Changes (not included)
   - M  src/lib/utils/format.ts
   - ??  tmp/scratch.js
   ```

   `### Review Loop Outputs` lists the dirty files from the reserved `review-loop` entry and is part of the commit set. Do not repeat those files under per-task Source Files. Excluded shared signals appear only under Unrelated Changes with their decision note.

   If there are no artifact files, no per-task tracked source files, AND no included review-loop outputs, inform the user that there is nothing to commit and STOP. When step 2a applies, STOP only when all three of its sets are empty of dirty paths — its artifact set, the dirty subset of its resolved source allowlist, and its spec sync set. A re-run against an already-committed archived change leaves all three empty and must reach this STOP rather than an empty commit; a still-dirty spec sync path must keep the flow going rather than be dropped here.

   When step 2a applies, add a `### Spec Sync Changes` section listing its spec sync set, and render Source Files as a single ungrouped list — none of step 2a's allowlist sources carry task granularity. When the allowlist came from the archive manifest, label that list with its origin and its snapshot nature.

6. **User confirmation**

   Use the **AskUserQuestion tool** to ask the user how to proceed.

   Options:
   - **Commit as shown**: Proceed with the displayed artifact + source files + `### Review Loop Outputs` (when step 2a applies, "as shown" also includes the Spec Sync Changes section)
   - **Include all dirty files**: Add all unrelated files to the commit as well. If this adds a shared signal previously excluded by user decision, first explain that it overturns that decision and obtain confirmation.
   - **Customize**: Let the user add or remove specific files from the commit set. Before adding a shared signal previously excluded by user decision, explain that it overturns that decision and obtain confirmation. When removing a shared signal previously included by user decision, move it to Unrelated Changes with the same `user-decision: excluded shared signal` note instead of making it disappear from the plan.
   - **Archive first, then commit together**: Run archive before committing — archive file moves will be included in this commit

   When step 2a applies, do NOT offer "Archive first, then commit together": the change is already archived, and running archive again fails with `change_not_found`.

   If the user selects "Customize":
   - Show a numbered list of all dirty files (included and excluded)
   - Ask which files to add or remove
   - Re-display the updated commit plan for confirmation

   If the user selects "Archive first, then commit together":
   - Proceed to step 6a (Archive sub-flow) before continuing to step 7

6a. **Archive sub-flow** (only when the user selected "Archive first, then commit together")

    This sub-flow executes three steps in sequence before returning to the main commit flow.

    **6a-i. Incomplete task handling**

    Read the tasks file at `openspec/changes/<name>/tasks.md`. Count `- [x]` (complete) and `- [ ]` (incomplete) checkboxes.

    - If **all tasks are complete**: skip to 6a-ii.
    - If **incomplete tasks exist**:
      - Display the list of incomplete tasks
      - Use the **AskUserQuestion tool** to ask: "These tasks are still incomplete. Mark all as complete before archiving?"
        - **Yes**: set a flag to pass `--mark-tasks-complete` to `"$cash_cli" archive`
        - **No**: cancel the archive sub-flow; do not invoke archive with incomplete tasks

    **6a-ii. Delta spec sync determination**

    Check whether delta specs exist at `openspec/changes/<name>/specs/` — they do not exist when the directory is empty or absent — then resolve the flag without asking the user.

    - **Explicit skip**: set the `--skip-specs` flag only when the user asked to skip delta spec sync in this invocation. This takes precedence over the default below.
    - **Default — no flag**: otherwise do not add `--skip-specs`, whether or not delta specs exist, and do NOT ask the user to choose.
    - MUST NOT infer a skip request from the change looking tooling-only or doc-only, from an earlier archive, or from any other indirect signal.

    Record the resolved outcome by evaluating in order: `skipped` (the flag is set), then `synced` (delta specs exist and the flag is not set), then `no delta specs` (no delta specs and the flag is not set). 6a-iii uses that recorded outcome, and only `synced` admits `openspec/specs/` paths into the commit set.

    **6a-iii. Archive execution and file collection**

    Execute the archive:

    ```bash
    "$cash_cli" archive <name> [--mark-tasks-complete] [--skip-specs]
    ```

    Before running archive, keep a copy of the already confirmed commit set:
    - Change artifacts collected before archive
    - Tracked source files from `.cash-skills/state/touched/<change-name>.json`
    - The confirmed `### Review Loop Outputs` set and every shared-signal decision
    - User customizations already confirmed before archive

    After archive completes successfully:

    1. Re-run `git status --porcelain` only to identify allowlisted archive outputs. Do not treat the full post-archive dirty state as archive output.
    2. Add only these archive-related file changes to the commit set:
       - Deletions under `openspec/changes/<name>/`
       - Additions or modifications under `openspec/changes/archive/<date>-<change>/`
       - Changes under `openspec/specs/` only when 6a-ii recorded the outcome `synced`
    3. Keep all other post-archive dirty files in Unrelated Changes unless they were part of the pre-archive confirmed commit set
    4. Display an **updated commit plan** showing all sections:

    ```
    ## Updated Commit Plan: <change-name> (with archive)

    **Spec sync:** <synced | skipped (explicitly requested) | no delta specs>

    ### Change Artifacts (archived)
    - D  openspec/changes/<name>/proposal.md
    - D  openspec/changes/<name>/tasks.md
    - ...

    ### Archived Files
    - A  openspec/changes/archive/<date>-<change>/proposal.md
    - A  openspec/changes/archive/<date>-<change>/tasks.md
    - ...

    ### Source Files
    (same as before)

    ### Review Loop Outputs
    (same confirmed set as before)

    ### Spec Sync Changes (if sync was performed)
    - M  openspec/specs/<spec-name>/spec.md
    - ...

    ### Unrelated Changes (not included)
    - D  .agents/skills/cash-apply/SKILL.md
    - M  notes/scratch.md
    ```

    Then continue to step 7.

7. **Generate commit message**

   Read the proposal file at `openspec/changes/<name>/proposal.md`. Extract the first sentence from the Why section (or Problem/Summary section if Why is absent). When step 2a applies, read the proposal and the tasks file from the resolved archive directory instead — the active change directory no longer exists.

   Generate a message in this format:

   ```
   cash(<change-name>): <summary>

   Change: <change-name>
   Tasks: <completed>/<total> complete
   ```

   If the archive sub-flow was executed (user selected "Archive first, then commit together"), add `Archived: yes` to the message body:

   ```
   cash(<change-name>): <summary>

   Change: <change-name>
   Tasks: <completed>/<total> complete
   Archived: yes
   ```

   Task progress comes from reading the tasks file and counting `- [x]` vs `- [ ]` checkboxes.

   Show the generated message to the user and allow editing before proceeding.

8. **Selective staging**

   Stage each confirmed file individually:

   ```bash
   git add <file1>
   git add <file2>
   ...
   ```

   **NEVER use `git add .` or `git add -A`.** Each file must be staged explicitly.

9. **Commit**

   ```bash
   git commit -m "<message>"
   ```

10. **Show result**

    ```bash
    git log --oneline -1
    ```

    Display the commit hash and message to confirm.
    If any shared signal was excluded by user decision, also list it and remind the user that the file remains dirty.

**Output On Success**

```
## Committed: <change-name>

**Commit:** <short-hash> cash(<change-name>): <summary>
**Files:** <N> files committed (<A> artifacts, <S> source files)
**Tasks:** <completed>/<total> complete
```

**Output On Nothing To Commit**

```
## Nothing to Commit

**Change:** <change-name>

No dirty files found for this change (no modified artifacts, no tracked source files).
```

**Guardrails**

- **NEVER use `git add .` or `git add -A`** — every file must be staged individually with `git add <file>`
- **NEVER commit files the user hasn't confirmed** — always show the file list and get explicit confirmation first
- If the tracking file is missing, warn but don't block — artifact-only commits are valid
- If **AskUserQuestion tool** is not available, ask the same questions as plain text and wait for the user's response
