---
name: cash-archive
description: "Archive a completed change. Use when every task is done and the change is ready to apply its delta specs."
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

Archive a completed change.

**Input**: Optionally specify a change name after `$cash-archive` (e.g., `$cash-archive add-auth`), optionally followed by `--skip-specs` to explicitly request skipping delta spec sync (see step 4). If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

**Prerequisites**: The project-local launcher initialized above is required. If root resolution, launcher validation, or a Cash command fails, report the exact error and STOP.

**Response language**: All user-facing responses in this workflow MUST be written in Traditional Chinese unless the user explicitly requests another language. Keep shell commands, file paths, code identifiers, schema field names, and quoted source text verbatim.

**Steps**

1. **If no change name provided, prompt for selection**

   Run `"$cash_cli" list --json` to get available changes. Use the **AskUserQuestion tool** to let the user select.

   Show only active changes (not already archived).
   Include the schema used for each change if available.

   **IMPORTANT**: Do NOT guess or auto-select a change. Always let the user choose.

2. **Check artifact completion status**

   Run `"$cash_cli" status --change "<name>" --json` to check artifact completion.

   Parse the JSON to understand:
   - `schemaName`: The workflow being used
   - `artifacts`: List of artifacts with their status (`done` or other)

   **If any artifacts are not `done`:**
   - Display warning listing incomplete artifacts
   - Record them for the complete preview plan in step 5
   - Do not request archive authorization here; the single authorization happens only after preview

3. **Check task completion status**

   Read the tasks file (typically `tasks.md`) to check for incomplete tasks.

   Count tasks marked with `- [ ]` (incomplete) vs `- [x]` (complete).

   **If incomplete tasks found:**
   - Display warning showing count of incomplete tasks
   - Use the **AskUserQuestion tool** to ask: "These tasks are still incomplete. Mark all as complete before archiving?"
     - **Yes**: set a flag to pass `--mark-tasks-complete` to the archive command in step 5
     - **No**: stop without archiving; do not invoke archive with incomplete tasks

   **If no tasks file exists:** Proceed without task-related warning.

4. **Determine spec sync behavior**

   Check for delta specs at `openspec/changes/<name>/specs/` — they do not exist when the directory is empty or absent — then resolve the flag without asking the user.

   - **Explicit skip**: pass `--skip-specs` only when the user asked to skip delta spec sync in this invocation — either by appending `--skip-specs` to the invocation, or by saying so directly in this session. This takes precedence over the default below.
   - **Default — sync**: otherwise run archive without `--skip-specs`, whether or not delta specs exist, and do NOT ask the user to choose.
   - MUST NOT infer a skip request from the change looking tooling-only or doc-only, from an earlier archive, or from any other indirect signal.
   - Record the resolved outcome by evaluating in order: `skipped` (the flag is set), then `synced` (delta specs exist and the flag is not set), then `no delta specs` (no delta specs and the flag is not set); step 6 reports it.

   Do not invoke another skill or delete touched state directly. The Cash CLI owns touched import, sync state, legacy cleanup diagnostics, transaction flags, and cleanup.

4b. **Uncommitted source guard**

   在執行 `"$cash_cli" archive` 之前，守門檢查 touched 允許清單中是否仍有未提交的 source 檔案——單獨封存會刪除 touched state，使後續 commit 失去來源允許清單。本步驟對 touched state 只讀不寫：MUST NOT 修改或刪除 `.cash-skills/state/touched/<name>.json` 或 `.spectra/touched/<name>.json`。

   - **取得 touched path set**：若 `.cash-skills/state/touched/<name>.json` 存在，讀取其 top-level `files` 欄位（CLI 驗證過的 canonical union）；若該檔不存在而 legacy 路徑 `.spectra/touched/<name>.json` 存在，改讀 legacy 檔 `touched` 陣列各條目 `files` 的聯集——legacy schema 的 top-level keys 恰為 `change` 與 `touched`，沒有 top-level `files`，MUST NOT 因此把合法 legacy 檔誤判為 malformed；步驟 5 的 CLI archive 會 import legacy touched state 後同樣刪除它，守門必須涵蓋同一 hazard。兩個 touched 路徑都不存在時，靜默通過本步驟，不發問也不顯示訊息。
   - **Malformed 放行**：touched 檔存在但無法依 current／legacy schema 安全取得合法的 path set 時——例如無法解析為 JSON、current 檔缺 top-level `files` 或其值不是 string array、legacy 檔缺合法 `touched` 陣列——MUST NOT 在 skill 層重製完整 CLI validator，不猜測、不修改任何檔案，直接放行進入步驟 5，由 CLI fail closed 並保留其實際 diagnostic：可能為 `state_invalid`、`touched_invalid` 或 `legacy_touched_invalid`，守門 MUST NOT 預判或替 CLI 斷定單一錯誤碼。
   - **取得 dirty 路徑**：在 project root 執行下列完整指令，並依 NUL-delimited 格式解析輸出：

     ```bash
     git status --porcelain=v1 -z --untracked-files=all
     ```

     條目涵蓋 staged、unstaged 與 untracked；每筆條目以兩字元狀態欄加一個空白開頭，比對前先剝除該前綴取出路徑；rename／copy 條目帶兩個 NUL 結尾路徑（先新路徑、後舊路徑），僅第一段帶狀態欄前綴，第二個 NUL field 是裸 old path，MUST NOT 對其剝除前綴——逐 field 套剝除規則會截掉舊路徑前三個字元，使 touched 檔被 rename 走時交集靜默漏判——新舊兩路徑皆計入 dirty 集合；`-z` 模式下路徑不做 C-quoting，可與 touched 中的 raw 路徑直接比對。
   - **偵測失敗停止**：該 git 指令以 non-zero 結束、或其輸出無法依 NUL-delimited 格式完整解析時，MUST NOT 把偵測失敗視同交集為空：停止 workflow、報告原始錯誤，且 MUST NOT 呼叫 `"$cash_cli" archive`。
   - **交集判定**：touched path set 與 dirty 路徑取交集。交集為空時，靜默通過本步驟，不發問也不顯示訊息。交集非空時，列出這些未提交的 source 檔案，用 **AskUserQuestion tool** 提供恰好兩個互斥選項：
     - **停止本次封存（建議）**：改執行 `$cash-commit` 並在確認選項選 `Archive first, then commit together`，讓封存與提交進同一個 commit；選此項時 MUST NOT 呼叫 `"$cash_cli" archive`。
     - **仍要單獨封存**：知悉封存會刪除 touched state、後續 `$cash-commit` 退回封存 manifest 的時間點快照的後果後，繼續步驟 5，不再重複發問。

5. **Build one archive preview and bind authorization**

   Resolve the three flags (`--skip-specs`, `--no-validate`, and `--mark-tasks-complete`) from this invocation. Run exactly one read-only JSON preview before asking for authorization:

   ```bash
   "$cash_cli" archive <name> --preview --json [resolved flags]
   ```

   The preview is a complete plan. Parse and display its `schema_version`, `change`, `preview_id`, `archived_id`, `archived_path`, `flags`, `incomplete_artifacts`, `incomplete_tasks`, `validation_findings`, `spec_updates`, `warnings`, and `cleanup_plan` together. Display any already-known Critical quality findings with their locations in the same authorization unit; if none are known, state that explicitly, and do not invent findings or run another review. The plan's `spec_updates` are informational; the skill MUST NOT apply or synchronize specs independently. The `archived_path` is a repo-relative path returned by the CLI.

   A preview error — including a collision, delta or touched-state error, pending recovery, or invalid arguments — stops this invocation. Report the exact structured error and MUST NOT retry, stage files, clean state, or call archive execution. A preview that reports incomplete artifacts, incomplete tasks, or validation findings remains visible in the same plan; only an explicitly confirmed matching flag can allow the core gate to continue.

   Ask for one authorization for the complete displayed plan, including the exact `preview_id`, selected flags, warnings, and cleanup implications. Cancellation or decline performs no checked execution and leaves the workspace unchanged.

6. **Revalidate and execute once**

   Immediately after authorization, execute exactly one checked archive with the same flags and identity:

   ```bash
   "$cash_cli" archive <name> --check-preview <preview_id> --json [same resolved flags]
   ```

   The CLI rebuilds the complete plan under its execution guard. If content, flags, destination, date, warnings, or any `preview_id` input changed, it returns `archive_preview_stale`; stop without retry. Any execution error also stops; this invocation has exactly one preview and exactly one checked execution, and MUST NOT retry or manually roll back a successful archive.

   On success, use only returned `archived_id` and returned `archived_path` verbatim. Do not construct an archive destination from a date, change name, repository root, or convention. Report `cleanup_warnings` and the `legacy_cleanup` diagnostic without re-reading or deleting state in the skill. A non-empty cleanup warning does not change proven archive success.

7. **Display summary**

   Show archive completion summary including the returned change, schema, `archived_path`, `archived_id`, `specs_status`, `applied_specs`, `cleanup_warnings`, and legacy cleanup diagnostic. Use the **Output On Success With Warnings** template whenever `warnings` or `cleanup_warnings` is non-empty; an explicit `skipped` outcome is itself a warning. The returned `archived_path` remains authoritative for every displayed location.

**Output On Success**

```
## Archive Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** <archived_path returned by the CLI>
**Specs:** ✓ Synced to main specs

All artifacts complete. All tasks complete.
```

**Output On Success (No Delta Specs)**

```
## Archive Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** <archived_path returned by the CLI>
**Specs:** No delta specs

All artifacts complete. All tasks complete.
```

**Output On Success With Warnings**

```
## Archive Complete (with warnings)

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** <archived_path returned by the CLI>
**Specs:** <✓ Synced to main specs | Sync skipped (explicitly requested by the user) | No delta specs>

**Warnings:**
- Archived with 2 incomplete artifacts
- Archived with 3 incomplete tasks
- Delta spec sync was skipped (explicitly requested by the user)

Review the archive if this was not intentional.
```

**Output On Error (Archive Exists)**

```
## Archive Failed

**Change:** <change-name>
**Target:** <path returned in the CLI error>

Target archive directory already exists.

**Options:**
1. Rename the existing archive
2. Delete the existing archive if it's a duplicate
3. Wait until a different date to archive
```

**Guardrails**

- Preserve .openspec.yaml when moving to archive (it moves with the directory)
- Never delete touched or sync state directly; archive owns ensure, transaction, cleanup, and each legacy cleanup diagnostic
- If **AskUserQuestion tool** is not available, ask the same questions as plain text and wait for the user's response

### No-spec archive presentation

`no-spec` 僅表示沒有 delta specs；預覽與 checked execution 仍必須顯示並驗證 `design.md`、`tasks.md`、implementation evidence、`preview_id`、validation findings、warnings、cleanup plan 與 transaction guard。輸出可標示 `Specs: No delta specs`，但不得因 schema 自動加入 `--skip-specs`、`--no-validate` 或其他 skip flag；只有本次使用者明確指定的 flag 才能傳入。no-spec capability／delta artifact conflict 仍由 CLI fail closed。保留一次 preview、一次 matching checked execution、destination／content identity 與 cleanup 診斷的原有保護，不能把 no-spec 當成免除 archive confirmation 或 validation 的捷徑。
