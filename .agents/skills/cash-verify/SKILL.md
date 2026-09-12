---
name: cash-verify
description: "Verify implementation matches artifacts. Use when a change needs task, requirement, and design conformance checked before archiving."
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

Verify that an implementation matches the change artifacts (specs, tasks, design).

**Input**: Optionally specify a change name after `$cash-verify` (e.g., `$cash-verify add-auth`). If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

**Prerequisites**: The project-local launcher initialized above is required. If root resolution, launcher validation, or a Cash command fails, report the exact error and STOP.

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

**Steps**

1. **If no change name provided, prompt for selection**

   Run `"$cash_cli" list --json` to get available changes. Use the **AskUserQuestion tool** to let the user select (if this tool is not available, ask as plain text and wait for the user's response).

   Show changes that have implementation tasks (tasks artifact exists).
   Include the schema used for each change if available.
   Mark changes with incomplete tasks as "(In Progress)".

   **IMPORTANT**: Do NOT guess or auto-select a change. Always let the user choose.

2. **Check status to understand the schema**

   ```bash
   "$cash_cli" status --change "<name>" --json
   ```

   Parse the JSON to understand:
   - `schemaName`: The workflow being used (e.g., "spec-driven")
   - Which artifacts exist for this change

3. **Get the change directory and load artifacts**

   ```bash
   "$cash_cli" instructions apply --change "<name>" --json
   ```

   This returns the complete apply consumer contract. Always read `state`, `missingArtifacts`, `preflight`, `contextFiles`, `progress`, and `tasks`.
   - `state: "blocked"`: report the non-empty `missingArtifacts` list and stop verification.
   - `state: "ready"`: inspect `preflight`, then verify the available implementation and report incomplete tasks normally.
   - `state: "all_done"`: inspect `preflight`, then perform the complete verification.
   - For either non-blocked state, a missing `preflight`, `missingFiles`, `driftedFiles`, or `staleness` field is a contract error. Report `critical` missing files and stop, show `warnings` before continuing, and silently continue for `clean`.
   - Any other state or missing required field is a contract error; report it and stop.
   - Read all available artifacts from `contextFiles`.

   Before mapping requirements, resolve the implementation scope through the shared read-only command:

   ```bash
   "$cash_cli" scope --change "<name>" [--base "<base-revision>"] [--support "<path>"]... --json
   ```

   Use the returned `scope_source`, `base_revision`, `head_revision`, `files`, `supporting_files`, `limitations` and `snapshot_id` as the evidence boundary. The selected `staged`, `unstaged`, `untracked` and, when explicitly requested, `committed` layers are the only implementation inputs. Every supporting path carries its HEAD/index/worktree typed states, corresponding content or tombstones, and an explicit base state when selected. Without an explicit `--base`, do not infer committed history. An empty scope is not a completed clean verification. Any declaration, type, callee, configuration or test read must first be listed with `--support`; rerun the same selector set with `--check-snapshot "<snapshot_id>" --json` before reporting. A `scope_insufficient`, `scope_stale` or `scope_unstable` result remains a limitation and cannot become a clean verification claim.

For a `no-spec` change, mark spec mapping, delta scenario and example checks as not applicable while still verifying `design.md`, `tasks.md`, execution evidence and current failures. A no-spec result does not authorize skipping required artifacts or evidence.

### No-spec verification handoff

對 `no-spec` change，驗證報告必須保留 `design.md`、`tasks.md`、implementation scope 與每項 execution evidence；spec mapping、delta scenario、example mapping 才標示為 `not applicable`。重用先前結果時，逐項比較其 `source_fingerprints`、`test_fingerprints`、`config_fingerprints` 與 `environment_fingerprints` 內容 identity；`contextRef` 只能證明 artifact context 相同，不能代替這些 identity，也不能證明測試通過。任一 identity 缺失或改變，先重新讀取對應內容並重跑必要檢查；本輪 current failure 優先於任何 prior pass。缺少 `design.md`、tasks、scope 或 evidence 時，保留具體缺口，不能因 no-spec 而完成驗證。

4. **Initialize verification report structure**

   Create a report structure with three dimensions:
   - **Completeness**: Track tasks and spec coverage
   - **Correctness**: Track requirement implementation and scenario coverage
   - **Coherence**: Track design adherence and pattern consistency

   Each dimension can have CRITICAL, WARNING, or SUGGESTION issues.

5. **Verify Completeness**

   **Task Completion**:
   - If tasks.md exists in contextFiles, read it
   - Parse checkboxes: `- [ ]` (incomplete) vs `- [x]` (complete)
   - Count complete vs total tasks
   - If incomplete tasks exist:
     - Add CRITICAL issue for each incomplete task
     - Recommendation: "Complete task: <description>" or "Mark as done if already implemented"

   **Spec Coverage**:
   - Parse the enclosing delta operation before evaluating coverage. For ADDED and MODIFIED, verify the required resulting behavior using the checks below. For REMOVED, verify that the removed obligation or behavior is absent as specified, including any migration expectations; do not demand its former implementation or scenarios. For RENAMED, verify the FROM/TO identity transition and preserved behavior, accounting for any accompanying MODIFIED block. Do not count a rename as a missing new implementation. Apply this operation-aware interpretation to all completeness, correctness, scenario, and example checks.
   - If delta specs exist in `openspec/changes/<name>/specs/`:
     - Extract ADDED and MODIFIED requirements (marked with "### Requirement:"); evaluate REMOVED and RENAMED separately as described above
     - For each requirement:
       - Search codebase for keywords related to the requirement
       - Assess if implementation likely exists
     - If requirements appear unimplemented:
       - Add CRITICAL issue: "Requirement not found: <requirement name>"
       - Recommendation: "Implement requirement X: <description>"

6. **Verify Correctness**

   **Requirement Implementation Mapping**:
   - For each ADDED or MODIFIED requirement from delta specs:
     - Search codebase for implementation evidence
     - If found, note file paths and line ranges
     - Assess if implementation matches requirement intent
     - If divergence detected:
       - Add WARNING: "Implementation may diverge from spec: <details>"
       - Recommendation: "Review <file>:<lines> against requirement X"

   **Scenario Coverage**:
   - For each scenario in ADDED or MODIFIED requirements (marked with "#### Scenario:"):
     - Check if conditions are handled in code
     - Check if tests exist covering the scenario
     - If scenario appears uncovered:
       - Add WARNING: "Scenario not covered: <scenario name>"
       - Recommendation: "Add test or implementation for scenario: <description>"

   **Example Traceability**:
   - For each `##### Example:` in ADDED or MODIFIED requirements:
     - Check if a test exists that uses the same input values from the example's GIVEN/WHEN/THEN
     - If the example has a table, check if parameterized tests cover all rows
     - If examples appear untested, add WARNING: "Spec example not covered by test: <example name>" with recommendation to add a test using the GIVEN/WHEN/THEN from the example

7. **Verify Coherence**

   **Design Adherence**:
   - If design.md exists in contextFiles:
     - Extract key decisions (look for sections like "Decision:", "Approach:", "Architecture:")
     - Verify implementation follows those decisions
     - If contradiction detected:
       - Add WARNING: "Design decision not followed: <decision>"
       - Recommendation: "Update implementation or revise design.md to match reality"
   - If no design.md: Skip design adherence check, note "No design.md to verify against"

   **Code Pattern Consistency**:
   - Review new code for consistency with project patterns
   - Check file naming, directory structure, coding style
   - If significant deviations found:
     - Add SUGGESTION: "Code pattern deviation: <details>"
     - Recommendation: "Consider following project pattern: <example>"

## Execution evidence protocol

For every named executable test、compiler、linter、CLI or other verification target, preserve恰好一個狀態；四態互斥：`passed-current`、`passed-prior`、`not-run`或`blocked`。一般執行失敗 MUST be `blocked` with `outcome_kind: failed`; an external unavailable prerequisite MUST be `blocked` with `outcome_kind: unavailable`，而 blocked evidence MUST preserve command、scope、result/diagnostic 與具體 blocker。Requirement mapping、scenario coverage、design adherence 等結論可保留，但純靜態 inspection MUST NOT算作 executed pass。

Each execution evidence record MUST contain `command`、`scope`、`result_source`、`result`，以及 `source_fingerprints`、`test_fingerprints`、`config_fingerprints`、`environment_fingerprints` 四組 gate-specific identity。每組 identity 要嘛列出目前值，要嘛以具體理由標為不適用；environment identity 至少涵蓋 working directory、執行檔/version 與 target 實際讀取的環境變數。合法 prior 來源只包含仍可引用的原始 command output/host record，或帶有上述完整 shape 的 repository-owned record；摘要性 prose 不是合法來源。

State selection uses deterministic precedence。任何 current execution outcome MUST優先於 `passed-prior`：current success MUST使用 `passed-current`，current failed/unavailable MUST使用對應的 `blocked` outcome kind，兩者都不得被 prior pass 遮蔽。只有本輪完全沒有可歸屬的 execution outcome 且決定重用 prior 時，才逐項比較 relevant identity；全部相符才可使用 `passed-prior`，任一 prior record/identity gate 缺失或不相符一律 `not-run`。後續相關 source、test、config 或 environment 變更會使舊的 current/prior pass 失效，必須重新分類。不得以 `blocked` 掩飾未嘗試。

本 protocol 不新增 Cash CLI command，也不建立新的持久化格式；evidence stays in the current verification handoff and the named command output。

8. **Generate Verification Report**

   **Summary Scorecard**:

   ```
   ## Verification Report: <change-name>

   ### Summary
   | Dimension    | Status           |
   |--------------|------------------|
   | Completeness | X/Y tasks, N reqs|
   | Correctness  | M/N reqs covered |
   | Coherence    | Followed/Issues  |
   ```

   **Issues by Priority**:
   1. **CRITICAL** (Must fix before archive):
      - Incomplete tasks
      - Missing requirement implementations
      - Each with specific, actionable recommendation

   2. **WARNING** (Should fix):
      - Spec/design divergences
      - Missing scenario coverage
      - Each with specific recommendation

   3. **SUGGESTION** (Nice to fix):
      - Pattern inconsistencies
      - Minor improvements
      - Each with specific recommendation

   **Final Assessment**:
   - If CRITICAL issues: "X critical issue(s) found. Fix before archiving."
   - If only warnings: "No critical issues. Y warning(s) to consider. Ready for archive (with noted improvements)."
   - If all clear: "All checks passed. Ready for archive."

**Verification Heuristics**

- **Completeness**: Focus on objective checklist items (checkboxes, requirements list)
- **Correctness**: Use keyword search, file path analysis, reasonable inference - don't require perfect certainty
- **Coherence**: Look for glaring inconsistencies, don't nitpick style
- **False Positives**: When uncertain, prefer SUGGESTION over WARNING, WARNING over CRITICAL
- **Actionability**: Every issue must have a specific recommendation with file/line references where applicable

**Graceful Degradation**

- If only tasks.md exists: verify task completion only, skip spec/design checks
- If tasks + specs exist: verify completeness and correctness, skip design
- If full artifacts: verify all three dimensions
- Always note which checks were skipped and why

**Output Format**

Use clear markdown with:

- Table for summary scorecard
- Grouped lists for issues (CRITICAL/WARNING/SUGGESTION)
- Code references in format: `file.ts:123`
- Specific, actionable recommendations
- No vague suggestions like "consider reviewing"

### Supporting snapshot lifecycle

Use only captured content for analysis. Before the first read of any supporting path, include it in `--support`. On support expansion, discard all findings, capture the complete selector set again, and restart analysis from that new content. Keep one external-drift rebuild budget across the entire analysis, including support expansions; expansion never resets the consumed budget. Before reporting, check the same complete support set with `--check-snapshot`. The first external drift discards findings and rebuilds the full scope once; a second external drift stops with an unstable limitation. An insufficient capture cannot produce a clean result.
