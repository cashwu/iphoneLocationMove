---
name: cash-audit
description: "Audit changed code for security sharp edges — dangerous defaults, type confusion, and silent failures. Use when an explicit security audit is requested for changed code."
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

Audit changed code for security sharp edges. This skill is report-only: it does not authorize edit, format, stage, or commit.

## Claude fork context

This Claude fork runs the shared audit contract as a report-only workflow. It MUST only execute the report core and return one consolidated report, then stop. It MUST NOT ask or wait for the user, MUST NOT modify or reformat files, MUST NOT stage or commit, and MUST NOT invoke follow-up workflow. If a decision or unique change identity is missing, return concrete context and missing input to the main thread; the main thread decides what happens next. Its execution topology is named below so the generated Codex variant can replace only that block.

---

## Shared Audit Contract

### Scope snapshot and dependency closure

Use the shared read-only scope command for every audit target:

```bash
"$cash_cli" scope [--change "<change-name>"] [--base "<base-revision>"] [--support "<path>"]... --json
```

Options and revisions are argv data. Without `--base`, inspect only current staged, unstaged and untracked layers; with `--base`, consume the explicit `base_revision` to `head_revision` committed layer and never guess history. Before reading a supporting declaration, type, callee, configuration or test, include it with `--support`; before reporting, rerun with the same selectors and `--check-snapshot "<snapshot_id>" --json`. Preserve `scope_source`, revisions, typed layers, supporting content and limitations in the read-only handoff. A `resolved` result permits analysis, an `empty` result does not mean a clean audit, and `scope_insufficient`／`scope_unstable` remains an explicit limitation.

Consume the complete typed candidate and supporting dependency closure from this one scope result. Capture each valid snapshot exactly once; the consumer MUST capture exactly once per valid snapshot. Do not run a second `git status --porcelain=v1 -z --untracked-files=all` or independently recapture the `staged layer`, `unstaged layer`, `untracked layer` or committed layer; the scope command already performs its bounded stability observations. Each layer carries a `present identity or absent tombstone`. An unscoped audit may omit `--change`; a change-scoped audit uses the validated touched allowlist. Do not stage files to inspect them.

Every candidate path has an independent typed state in the HEAD, index, and worktree layers:

- A present HEAD or index state records the blob OID and mode; an absent state records a tombstone.
- A present worktree state records bytes, file type, mode, device, and inode; an absent state records a tombstone.
- A deleted entry never assumes that the index or worktree still has a blob.
- A rename keeps old／new path provenance, and each old and new path independently records present or tombstone state in every layer.

When an analyzer actually reads a supporting declaration, type, callee, configuration, or test path, add it on its first read to the analysis dependency closure with the path's HEAD/index/worktree typed states (and base state when explicitly selected) plus corresponding readable content or absent tombstone. A read that cannot be added makes coverage incomplete. Capture and read command errors, binary or unreadable content, and unattributable dirty items are limitations; they are never a clean shortcut.

Before the report, revalidate the same typed fields, layer identities, dependency closure, and limitations. On the first detected drift, discard findings and perform one complete rebuild. If a second drift occurs after that rebuild, stop with an `unstable` limitation and do not claim a completed clean audit.

### Risk classification

Classify the captured snapshot once with mutually exclusive precedence. The branches are ordered as follows:

1. Any hunk that affects public API, wire／compatibility contract, configuration／defaults／feature flags／permissions, authentication／authorization／session／secret／cryptography, input validation／parsing／deserialization／type conversion, filesystem／process／network／IPC boundary, or an error path that may mask failure is `sensitive` and enters `deep mode`.
2. Content that does not match `sensitive` but whose boundary or downstream effect cannot be classified with confidence is `uncertain` and enters `deep mode`.
3. Only content that missed both earlier branches and is reliably presentation, documentation, tests, or internal behavior outside a security boundary is `ordinary mode`.

The first matching branch wins. A later fallback MUST NOT lower `sensitive` or `uncertain` to `ordinary mode`. Binary and unreadable content is both a limitation and `uncertain`; it is not an excuse to skip deep analysis.

For `ordinary mode`, one analyzer applies all three lenses in a single pass and dispatches no child agents. For `deep mode`, each lens receives a filtered packet containing only the related diff hunk and file／line anchor, the minimum supporting declarations／types／callees, relevant configuration／defaults／validation／boundary definitions, and tests that support or refute the behavior. The packet excludes unrelated hunks（排除無關 hunks）.

### Execution topology

#### Claude fork topology

Claude fork applies the same filtered packet sequentially through Scoundrel, Lazy Developer, and Confused Developer. It has no child-agent dispatch obligation, and it never drops a lens because a tool cannot dispatch children.

## Report contract

An audit-only request produces a consolidated report and does not authorize edit, format, stage, or commit. A finding is eligible only when it has severity, a file／line anchor, changed behavior 與 supporting evidence, a concrete failure scenario, a recommended fix, and its 來源 lens. Discard candidates that have only a label or speculation. A completed clean audit requires a complete scope, every readable item analyzed by all three lenses, a successful dependency-closure check, and successful snapshot revalidation; otherwise report limitations and unverified paths rather than a clean result.

## Core Framework

### Three Adversaries

| Role | Mindset | Key Questions |
| --- | --- | --- |
| **Scoundrel** | Malicious, deliberate exploitation | Can I disable security via config? Downgrade algorithms? Inject values? |
| **Lazy Developer** | Copy-paste, skips docs, deadline pressure | Is the first example safe? Is the default secure? Do errors guide me right? |
| **Confused Developer** | Misunderstands usage | Can I swap params silently? Will mistakes fail loudly? Are types distinguishable? |

### Six Trap Categories

#### 1. Algorithm Choice Traps

Letting developers choose algorithms invites them to choose the wrong one. Prefer a safe fixed algorithm or a semantic type that cannot accept an unsafe downgrade.

#### 2. Dangerous Defaults

Check zero, empty, and nil values. Insecure defaults cannot be grandfathered for backwards compatibility; deprecate them loudly and require migration.

#### 3. Raw Primitives vs Semantic Types

Look for swappable strings or bytes in security-sensitive interfaces. Prefer types that distinguish keys, nonces, permissions, and other roles.

#### 4. Configuration Cliffs

Check whether one typo or combination disables authentication, validation, transport security, or other boundaries without a loud failure.

#### 5. Silent Failures

Check whether security errors surface and whether callers must observe a result instead of accidentally masking failure.

#### 6. Stringly-Typed Security

Prefer enums or constrained values over concatenated security-critical strings.

### Severity Classification

| Severity | Condition |
| --- | --- |
| Critical | Default or most obvious usage is insecure |
| High | Easy misconfiguration breaks security |
| Medium | Uncommon but possible misconfiguration |
| Low | Requires deliberate misuse |

## Discipline Mode

When referenced by `$cash-apply` through `"$cash_cli" instructions --skill audit`, do not launch child agents. Apply the same Scoundrel, Lazy Developer, and Confused Developer checklist continuously during implementation. The standalone audit remains report-only; this discipline does not change `cash-apply` edit authorization.

### Quick 3-Role Check

1. **Scoundrel**: Can this be abused? Can config disable security? Can values be injected?
2. **Lazy Developer**: Is the default safe? Will copy-paste usage be secure? Does the error message guide correctly?
3. **Confused Developer**: Can params be swapped? Will wrong usage fail loudly? Are types distinct enough?

Focus on new function signatures and public APIs, configuration options and defaults, authentication／authorization／encryption interfaces, input validation and error handling at system boundaries, and any security-relevant choice.

---

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

### Supporting snapshot lifecycle

Use only captured content for analysis. Before the first read of any supporting path, include it in `--support`. On support expansion, discard all findings, capture the complete selector set again, and restart analysis from that new content. Keep one external-drift rebuild budget across the entire analysis, including support expansions; expansion never resets the consumed budget. Before reporting, check the same complete support set with `--check-snapshot`. The first external drift discards findings and rebuilds the full scope once; a second external drift stops with an unstable limitation. An insufficient capture cannot produce a clean result.
