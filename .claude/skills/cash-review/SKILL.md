---
name: cash-review
description: "Review implementation quality for a Cash change with a report-only, change-scoped workflow. Use when implementation is ready for correctness, efficiency, reuse, and convention review."
argument-hint: "[change-name] [base-revision]"
context: fork
agent: Explore
disallowed-tools: [Edit, Write]
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

## Claude fork context

This generated Claude Code skill runs with `context: fork` as a report-only workflow. It MUST only execute the report core and return one consolidated report, then stop. It MUST NOT ask or wait for the user, MUST NOT modify or reformat files, MUST NOT stage or commit, and MUST NOT invoke follow-up workflow. If a decision or unique change identity is missing, return concrete context and missing input to the main thread; the main thread decides what happens next. Recommendations may appear in the report, but the caller decides whether anything should be fixed.

---

Review implementation quality for a Cash change. This is a standalone code review, not artifact analysis, spec verification, security audit, or drift detection.

**Input**: Optionally specify a change name after `/cash-review` (for example, `/cash-review add-auth`). If no name is supplied, use a unique confirmed conversation target. If neither exists, run `"$cash_cli" list --json` and select only when exactly one active change is returned; otherwise report the candidate list or empty state and ask the main thread to rerun `/cash-review <change-name>`.

**Prerequisites**: The project-local launcher initialized above is required. If root resolution, launcher validation, or a Cash command fails, report the exact error and STOP.

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

## 1. Load intent context

Read the change's proposal, design, specs and tasks when available. Use them to understand intent and named scope; do not turn this review into `cash-analyze`, `cash-verify`, `cash-audit` or `cash-drift`.

## 2. Resolve a read-only review scope

1. Resolve the Git root and read the existing state file at `.cash-skills/state/touched/<change-name>.json` using a no-follow, read-only open. MUST NOT call `"$cash_cli" touched ensure "<change-name>"` or any other command that writes state.
2. Validate the parsed state before using it: `version` is supported, `change` equals the selected name, top-level `files` is a list of safe repository-relative files, and every task entry's `files` is a safe list. Reject missing, malformed, symlinked, non-regular or inconsistent state as `scope insufficient`; never repair it in this workflow.
3. Invoke the shared read-only scope command with the selected change and an explicit base when history is intended:

   ```bash
   "$cash_cli" scope --change "<change-name>" [--base "<base-revision>"] [--support "<path>"]... --json
   ```

   Pass every option as argv data. A missing `--base` means current staged, unstaged and untracked layers only; never infer history from dates or the first commit. Add a supporting declaration, type, callee, configuration or test path with `--support` before reading it, then use `--check-snapshot "<snapshot_id>" --json` with the same `--change`, `--base` and complete support set before reporting.
4. Consume `schema_version`, `status`, `scope_source`, `change`, `base_revision`, `head_revision`, `files`, `supporting_files`, `limitations` and `snapshot_id` from the result. A resolved scope may include `committed`, `staged`, `unstaged` and `untracked` layers; an empty scope is not a completed clean review. Treat untracked text as added content. Mark binary or unreadable content as unverified.
5. If the command reports `insufficient`, `scope_unstable` or a limitation that prevents complete inspection, report it and stop the clean-review claim. An explicit `--base` may produce a resolved committed-only scope; preserve that selected history and report its layers. A `0 findings` result is valid only after every selected inspectable file and all four lenses have been reviewed.
6. Capture the state file's bytes, file type, mode, device and inode identity, and retain the scope revisions, every candidate layer identity, every supporting path's HEAD/index/worktree (and explicit base) layer identities and content, and limitations in the report. Read only the selected paths and the nearby tests, helpers and call sites needed to check a finding. The state file and workspace must remain unchanged.
7. Before generating the report, repeat the same scope command with the same selectors and check its snapshot. If anything changed, discard the old scope and findings, rebuild once and repeat the check. If the second check still drifts, stop with an `unstable` limitation and do not claim clean.

The workflow is report-only. It MUST NOT modify, format, create, delete, stage or commit files.

## 3. Review four lenses

These are search lenses, not finding quotas. Do not add weak findings to fill a category.

- **Correctness**: logic, edge cases, state transitions, stale data and error paths under realistic inputs.
- **Efficiency**: repeated work, blocking, algorithmic cost, wasteful I/O and process spawning.
- **Simplification/reuse**: duplication, overlooked helpers, avoidable abstractions and behavior-preserving simplifications.
- **Convention**: divergence from local naming, boundaries, patterns or generated-output rules that creates maintenance risk.

## 4. Build and re-check findings

Every finding MUST contain all of the following:

- a file and line anchor (`path/line`);
- a one-sentence defect summary;
- a concrete failure scenario naming the input, state or sequence and the wrong behavior;
- severity: `Critical`, `Warning` or `Suggestion`;
- `basis: rule violation` or `basis: reviewer judgement`;
- a specific recommendation.

For `basis: rule violation`, cite the exact project document, spec, design or existing-code convention that is violated. If no source can be cited, use `basis: reviewer judgement`; never present preference as a rule. Style-only nits, checklist-only observations and speculative refactors are not findings.

Before reporting each candidate, perform an adversarial re-check against nearby tests, helpers and call sites. Try to prove that the behavior is already handled or that the failure scenario cannot occur; drop the candidate when it is speculative, already fixed or ungrounded.

Sort findings by severity (`Critical`, then `Warning`, then `Suggestion`) and output at most 20. If more than 20 remain after the re-check, output the first 20 in that order and explicitly state that the result was truncated.

## 5. Report

Use this shape:

```markdown
## Review Report: <change-name>

Scope source: existing touched state; status: <resolved | empty-unverified | insufficient | unstable>
Revisions: <HEAD observed during scope>; current layers: staged, unstaged, untracked
Reviewed files: <paths>
Limitations / unverified content: <limitations and paths, or none>

Dimensions reviewed: correctness, efficiency, simplification/reuse, convention

### Findings

1. **<Severity>** `<file>:<line>` — <one-sentence defect summary>
   Basis: <rule violation — cited source location | reviewer judgement>
   Failure scenario: <specific input/state/sequence and wrong behavior>
   Recommendation: <specific fix direction>
```

With 0 findings, say `0 findings` and list the reviewed files and all four dimensions. A completed clean review requires a sufficient scope, current inspectable content and a successful second identity check. Missing/invalid touched state, an empty selected scope, binary/unreadable files or unstable scope MUST remain visible as limitations; they MUST NOT be converted into a clean result.

## Boundaries

- `cash-analyze` checks artifact consistency before implementation.
- `cash-verify` checks implementation against requirements, scenarios, tasks and design.
- `cash-audit` checks security sharp edges such as dangerous defaults, type confusion and silent failures.
- `cash-drift` checks whether an older change's artifacts have become stale.
- `cash-review` checks implementation quality in the current touched dirty layers and returns a report only.

Do not invoke a follow-up workflow from this skill.

### Supporting snapshot lifecycle

Use only captured content for analysis. Before the first read of any supporting path, include it in `--support`. On support expansion, discard all findings, capture the complete selector set again, and restart analysis from that new content. Keep one external-drift rebuild budget across the entire analysis, including support expansions; expansion never resets the consumed budget. Before reporting, check the same complete support set with `--check-snapshot`. The first external drift discards findings and rebuilds the full scope once; a second external drift stops with an unstable limitation. An insufficient capture cannot produce a clean result.
