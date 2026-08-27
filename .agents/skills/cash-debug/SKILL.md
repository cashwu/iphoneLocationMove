---
name: cash-debug
description: "Systematically debug a problem using a four-phase workflow"
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

Systematically debug a problem using a four-phase workflow.

**This skill enforces debugging discipline.** No guessing, no random changes, no "let me try this." Every step is deliberate and evidence-based.

**Input**: The argument after `$cash-debug` describes the bug or unexpected behavior. Examples:

- `$cash-debug the search returns duplicate results`
- `$cash-debug crash on startup after upgrading`
- `$cash-debug file watcher misses rename events`

---

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

## The Three-Attempt Rule

**Maximum 3 fix attempts per hypothesis in Phase 4 (Fix).** Phases 1-3 (Reproduce, Isolate, Root Cause) are investigation — they do not count toward this limit. If your third fix attempt fails:

1. **Stop fixing**
2. Document what you tried and why it failed
3. Question your hypothesis — is the root cause what you think it is?
4. Research alternatives or try a completely different angle

Do NOT keep trying variations of the same approach. That's a loop, not debugging.

---

## Phase 1: Reproduce

Before anything else, make the bug happen reliably.

- **Find the exact steps** to trigger the bug
- **Identify the expected vs actual behavior** — be precise
- **Determine if it's consistent** — does it happen every time? Only on certain input?
- **Simplify the reproduction** — strip away everything that's not essential

If you can't reproduce it, you can't debug it. Gather more information before proceeding.

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

**Don't stop at the first explanation.** Verify your hypothesis:

- Can you predict the bug's behavior based on your theory?
- Does your theory explain ALL the symptoms, not just some?
- Can you construct a test case that proves the root cause?

**Record the verification evidence carrier.** Before leaving Phase 3, write into your debug notes exactly one primary verification target, the related regression targets, the success marker, and — when a red phase applies — the failure marker, or `N/A` with a pure-refactor or remaining-task classification reason. These notes are this workflow's evidence carrier; `cash-debug` does not run inside a Cash task loop and MUST NOT assume a `tasks.md` contract exists.

---

## Phase 4: Fix

Now — and only now — fix the bug.

Read `.cash.yaml` in the project root first. If `tdd: true` is set, fetch TDD instructions by running `"$cash_cli" instructions --skill tdd`, then follow the returned `instruction`, consuming the Phase 3 notes as its named targets and markers. If `tdd: false` is set, do not force a fail-first ordering.

Regardless of the `tdd` value, when the fix will add or modify any test, fetch test-quality instructions by running `"$cash_cli" instructions --skill test-quality` before the first test edit, then follow the returned `instruction`.

The numbered order below is the `tdd: false` sequence. Under `tdd: true` the fetched `instruction` owns the ordering: when it classifies this bug as a red-phase branch, run the Phase 3 primary verification target and observe its failure marker before any production edit, then follow the numbered steps from step 1.

1. **Make the minimum change** to fix the root cause — not the symptoms
2. **Run the Phase 3 primary verification target** — confirm its success marker appears
3. **Run the Phase 3 regression targets** — ensure no regressions
4. **Check related code** — if this pattern exists elsewhere, fix those too

Both `tdd` values require root-cause analysis first, a minimum root-cause fix, a named primary verification target, and the related regression targets. When no practical automated test boundary exists, use the CLI, analyzer, or manual assertion that suits the problem.

---

## Guardrails

- **Don't guess** — Every change must be based on evidence
- **Don't fix symptoms** — Find and fix the root cause
- **Don't skip verification** — every fix runs the Phase 3 primary verification target and the related regression targets
- **Don't power through** — After 3 failed attempts, stop and reassess
- **Do keep notes** — Document what you tried, what you found, what you ruled out
- **Do check broadly** — A bug in one place often means the same bug exists elsewhere
