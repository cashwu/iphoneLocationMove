---
name: cash-debug
description: "Systematically debug a problem using a four-phase workflow. Use when a persistent problem needs reproduce, isolate, root-cause, fix, and integration work."
argument-hint: "[problem|change-name task-id]"
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

Systematically debug a problem using a five-phase workflow.

**This skill enforces debugging discipline.** No guessing, no random changes, no "let me try this." Every step is deliberate and evidence-based.

**Input**: The argument after `/cash-debug` describes the bug or unexpected behavior. Examples:

- `/cash-debug the search returns duplicate results`
- `/cash-debug crash on startup after upgrading`
- `/cash-debug file watcher misses rename events`

---

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

## The Three-Attempt Rule

**Maximum 3 fix attempts per hypothesis in Phase 4 (Fix).** Phases 1-3 (Reproduce, Isolate, Root Cause) are investigation — they do not count toward this limit. If your third fix attempt fails:

1. **停止修復**
2. Document what you tried and why it failed
3. Question your hypothesis — is the root cause what you think it is?
4. Research alternatives or try a completely different angle

Do NOT keep trying variations of the same approach. That's a loop, not debugging.

---

## Phase 1: Reproduce

Before anything else, make the bug happen through an executed test, trace replay, or measured experiment. A Phase 1 note MUST record all of these evidence fields:

- `expected behavior` and `actual behavior`
- `trigger input／steps`
- the executed `command or observation method`
- `environment`
- `sample count` and `failure count`
- `symptom match`

For an intermittent symptom, establish the failure-frequency baseline with multiple comparable samples, then use comparable samples again after the fix. A single successful sample is a `one passing sample`, not evidence that the problem disappeared. Owner-supplied logs, screenshots, and reports can support a clearly labeled `static investigation` and hypothesis formation, but they cannot establish completed reproduction or a completed fix without execution evidence.

Only an executed test, trace replay, or measured experiment that observes the target symptom match passes the reproduce gate and permits Phase 2. If the symptom cannot be safely executed, 停止 at the reproduce gate and list the missing authorization, environment, or input; do not infer a reproduction from static material.

---

## Phase 2: Isolate

Narrow down where the bug lives.

- **Binary search the codebase** — which module, which function, which line?
- **Check inputs and outputs** — at each boundary, is the data correct?
- **Add targeted logging** — not everywhere, just at decision points
- **Use git bisect** when the bug is a regression — find the exact commit that introduced it

Goal: pinpoint the exact location where behavior diverges from expectation.

---

## Phase 3: Root Cause

Understand WHY it's broken, not just WHERE.

Ask these questions:

- What assumption is being violated?
- What changed that made this start failing?
- Is this a symptom of a deeper issue, or the actual problem?
- Are there other places with the same pattern that might also be affected?

**Don't stop at the first explanation.** For every root-cause hypothesis, record `supporting evidence`, a `falsifiable prediction`, and a minimal `distinguishing experiment`. Rank candidates by evidence ranking and run the highest-ranked experiment first. When evidence refutes a candidate, explicitly discard or downgrade it; do not rewrite the same guess as a new hypothesis.

Verify the leading hypothesis:

- Can you predict the bug's behavior based on your theory?
- Does your theory explain ALL the symptoms, not just some?
- Can you construct a test case that proves the root cause?

**Record the verification evidence carrier.** Before leaving Phase 3, write into your debug notes exactly one primary verification target, the related regression targets, the success marker, and — when a red phase applies — the failure marker, or `N/A` with a pure-refactor or remaining-task classification reason. These notes are the Phase 3 evidence carrier; `cash-debug` does not run inside a Cash task loop and MUST NOT assume a `tasks.md` contract exists.

---

### Integration preflight（Phase 4 前）

在 Phase 3 evidence carrier 完成後、Phase 4 的首次 edit 前，執行 Integration preflight。先用 project-local Cash CLI `"$cash_cli" list --json` 列出 active changes，並保存非空 predicted fix path set 與 primary verification target。這個 preflight 必須在 before the first edit 的時點完成，不能用事後 diff 補建 snapshot。

使用者明確提供 explicit `(change, task-id)` 時，先驗證 change active、task exists and is pending；有效 reference 的 candidate set 只包含該 task。若 reference 無效，記錄 reference gap，Phase 5 分類為 insufficient，MUST NOT be classified as standalone，不能以空 candidate set 掩蓋無效 reference。

沒有有效 explicit reference 時，candidate set 只包含 `delivery` 可解析、且 delivery path set 與 predicted fix path set 有非空交集的 pending tasks。description-only match 不建立 candidate；delivery-only but path-disjoint 也不建立 candidate；description mismatch does not filter a delivery intersection，只要其餘 eligibility evidence 完整即可繼續判定。

Candidate 只有同時符合下列條件才是 candidate eligible：predicted fix paths 是 delivery path set 的非空子集；primary verification target 與 task 的 `verification` 或 `regression` target 之一 byte-exact 相同；five task evidence fields（`delivery`、`verification`、`regression`、`success`、`red`）完整；相關 requirement 可由已讀 artifacts 識別。

只有 candidate set exactly one 且 candidate eligible 時，才執行 `"$cash_cli" in-progress add "<name>"` 並保存 pre-fix snapshot；snapshot 必須在 before the first edit 已存在且可讀。只有 change 名稱而沒有 task-id 不會改變 candidate 規則。

## Phase 4: Fix

Now — and only now — fix the bug.

Read `.cash.yaml` in the project root first. Preserve the existing TDD toggle semantics. If `tdd: true` is set, fetch TDD instructions by running `"$cash_cli" instructions --skill tdd`, then follow the returned `instruction`, consuming the Phase 3 notes as its named targets and markers. If `tdd: false` is set, do not force a fail-first ordering.

Regardless of the `tdd` value, when the fix will add or modify any test, fetch the test-quality instruction consumer by running `"$cash_cli" instructions --skill test-quality` before the first test edit, then follow the returned `instruction`.

The numbered order below is the `tdd: false` sequence. Under `tdd: true` the fetched `instruction` owns the ordering: when it classifies this bug as a red-phase branch, run the Phase 3 primary verification target and observe its failure marker before any production edit, then follow the numbered steps from step 1.

1. **Make the minimum change** to fix the root cause — not the symptoms
2. **Run the Phase 3 focused primary reproducer** — confirm its success marker appears
3. **Run the related regression targets** — ensure no regressions
4. **Report same-pattern follow-up** — list each out-of-scope path and its evidence; do not modify it unless the user explicitly expands scope

Only demonstrated dependency impact, a cross-module change, or project policy can justify running the full suite after the focused primary reproducer and related regression targets. Record the selected trigger or the reason the full suite was not run in the notes. The focused primary reproducer always precedes the related regression targets.

Both `tdd` values require root-cause analysis first, a minimum root-cause fix, a named primary verification target, and the related regression targets. When no practical automated test boundary exists, use the CLI, analyzer, or manual assertion that suits the problem.

---

## Phase 5: Integration

## Phase 5 Integration classification

Phase 5 Integration SHALL use an ordered, exhaustive partition；前一分支命中後不得再分類：

1. **matched**：explicit reference 已解析或未提供、candidate set exactly one、candidate eligible、requirement／verification／pre-fix snapshot evidence 完整，且非空 actual changed endpoint set 是 task delivery path set 的非空子集。Dispatch 前保存完整原始 task description；tracking 前重取 full apply instructions 與 compact schedule，以 byte-exact 原 description 唯一配對目前 CLI ordinal，並確認仍為同一 pending/ready task。缺失、多重配對或 contract 改變時停止，不使用 stale ordinal。只有 matched、完成上述配對且 verification complete 才由 main thread 執行 `"$cash_cli" task done --change <name> <task-id> --path <path>`，只傳本次實際 modified、added、deleted paths，以及 rename 的新舊 endpoints。
2. **insufficient**：explicit reference 無效、candidate set 非空但大小不為一，或唯一 candidate 的 eligibility、requirement、verification、snapshot、actual-path subset、deleted／renamed endpoint evidence 任一不完整；這些情況保持 task pending，不執行 task tracking，MUST NOT 執行 `task done`。Snapshot 直到 edit 後才建立、缺失或失效，或實際變更含 delivery 外 endpoint，都屬此分支並回報 artifact/scope mismatch。
3. **standalone**：只有未提供 explicit reference 且 candidate set 為空時才成立。Standalone branch MUST NOT 修改 Cash state、MUST NOT 自動建立 change 或擴張修復範圍；若需要正式後續工作，只建議 `$cash-propose`。

Deleted／renamed endpoint evidence 必須逐端點驗證：rename old endpoint 與 deletion path 必須有 pre-fix snapshot or same-task prior attribution；rename new endpoint 必須有 post-fix current-state evidence；新舊 endpoint 都傳給 task done。unchanged regression test path 只留在 verification evidence，MUST NOT 進入 touched attribution。MUST NOT 從 whole-worktree diff 歸屬；若 actual changed endpoint set 超出 delivery path set，保持 task pending。

## Reader-facing output contract

四個 workflow 的 user-visible status、question、heading 與 summary MUST 先說明結果與下一步，再提供 diagnostics、locations 與其他證據。Cash 內部術語首次出現時，必須用一句繁體中文說明它對使用者的意義。固定 user-visible literals 使用繁體中文：`使用計畫檔`、`使用對話內容`、`完成`、`開始實作`、`使用 change：`、`仍要繼續`、`停止`、`修正後繼續`、`繼續執行…`、`實作完成`、`本次完成`、`實作已暫停`、`遇到的問題`、`Artifacts 一致`、`發現 N 個問題，正在修正（第 M/2 次）`、`使用 TDD`、`不使用 TDD`。commands、paths、identifiers、schema fields 與 quoted source text MUST 保持 verbatim；不得以 emoji、顏色或僅有格式差異承載唯一狀態。

## Guardrails

- **Don't guess** — Every change must be based on evidence
- **Don't fix symptoms** — Find and fix the root cause
- **Don't skip verification** — every fix runs the Phase 3 primary verification target and the related regression targets
- **Don't power through** — After 3 failed attempts, stop and reassess
- **Do keep notes** — Document what you tried, what you found, what you ruled out
- **Do check broadly** — A bug in one place often means the same bug exists elsewhere

## Context and schedule reuse

When the debug target is a Cash change, obtain the summary apply view for orientation and the compact apply view before selecting a task. Read `schemaName` and `schedule` from apply and `task_order` from change metadata. Artifact-level `contextRef` only governs previously fetched artifact context; apply views do not return it. A missing or changed artifact reference, compaction loss or current failure requires the relevant full instructions. Re-fetch canonical discipline instructions if their runtime version is unknown or their full text was lost. Use dependency `ready_ids` and `blocked_ids` as the execution boundary and save the task's full original description byte-for-byte for the main thread; CLI ordinals are current positions, not stable identity. Re-fetch tasks and uniquely match that description to the current pending/ready ordinal before completion; missing or duplicate matches stop tracking, and a stale ordinal must never be reused.
