---
name: cash-analyze
description: "Analyze artifact consistency for a change. Use when a named change's proposal, design, specs, and tasks may conflict before implementation."
argument-hint: "[change-name]"
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

This generated Claude Code skill runs with `context: fork`. The rules in this section take precedence over the shared `analyze` body below.

This fork is report-only: it MUST only execute the report core and return one consolidated report, then stop. It MUST NOT ask or wait for the user, MUST NOT modify or reformat files, MUST NOT stage or commit, and MUST NOT invoke follow-up workflow. If a decision or unique change identity is missing, return concrete context and missing input to the main thread; the main thread decides what happens next.

When no change name is provided, run `"$cash_cli" list --json`. Auto-select only when there is exactly one active change. If there are zero active changes or more than one active change, return the candidate list or empty-state message and ask the main thread to rerun `/cash-analyze <change-name>`. Do NOT ask an interactive selection question inside the fork.

---

Analyze artifact consistency for a change. Can be invoked directly or triggered automatically when all artifacts are complete.

**Input**: Optionally specify a change name (e.g., `/cash-analyze add-auth`). If omitted, infer from conversation context or auto-select if only one active change exists.

**Prerequisites**: This skill requires the `Cash` CLI. If any `Cash` command fails with "command not found" or similar, report the error and STOP.

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

**Steps**

1. **Determine change name**

   If not provided, infer from context or run `"$cash_cli" list --json` to auto-select.

2. **Run programmatic analysis**

   ```bash
   "$cash_cli" analyze <change-name> --json
   ```

   This returns structured JSON with:
   - `dimensions`: Array of `{ dimension, status, finding_count }` for Coverage, Consistency, Ambiguity, Gaps
   - `findings`: Array of `{ id, dimension, severity, location, summary, recommendation }`
   - `artifacts_analyzed` / `artifacts_missing`: Which artifacts were available

3. **Run mandatory semantic analysis**

   Read the available artifacts and apply the Semantic traceability contract below to every supported dimension. Semantic analysis is required: check mutually exclusive decisions, orphan tasks, risk dispositions and cross-artifact path/behavior contradictions. Preserve schema-aware skipped/insufficient dimensions and every current validation failure.

4. **Present one consolidated report**

   Only after CLI and semantic analysis finish, output one summary table for Coverage, Consistency, Ambiguity and Gaps, then group the merged findings by severity with locations, causal evidence and concrete recommendations. Do not present the structural report early or treat semantic checks as optional.

5. **Recommend next steps**
   - If CRITICAL findings: "Found N issue(s) worth addressing. Want to fix these before implementing?"
   - If only warnings/suggestions: Note them briefly, then recommend proceeding with `/cash-apply`
   - If clean: "Artifacts look consistent" and suggest `/cash-apply`

**Passive Trigger**

When `"$cash_cli" status --change "<name>" --json` shows `isComplete: true`, run this analysis automatically before recommending `/cash-apply`.

**Guardrails**

## Semantic traceability contract

Run the CLI analysis and semantic checks as one bounded analysis, then emit one consolidated report. Classify each semantic finding into exactly one dimension: mutually exclusive decisions are `Warning`, and a decision that blocks implementation is `Critical`; a task isolated from the declared scope is `Suggestion`; a design risk without a traceable disposition is `Warning`; and a contradiction across artifact paths or observable behavior is `Warning`. Every finding records its artifact scope or location, the causal evidence, and the affected requirement or task.

An effective risk disposition is one of a requirement or scenario, a concrete mitigation, an executable verification task, or the user's explicit acceptance. An agent-authored `intentional` note is not user acceptance. A resolved risk is removed from `uncovered-risk` only after its disposition is traceable; existing safety exceptions and mutually exclusive decisions remain visible. For no-spec changes, mark spec mapping and scenario/example checks as not applicable while retaining design, tasks, execution evidence and current validation failures.

- Read-only: NEVER modify files
- Keep output concise - this runs inline, not as a separate workflow
- If **AskUserQuestion tool** is not available, ask the same questions as plain text and wait for the user's response
