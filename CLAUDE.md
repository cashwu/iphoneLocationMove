<!-- CASH:START -->

本專案所有面向使用者的回覆一律以繁體中文撰寫，除非使用者明確要求其他語言。shell 指令、檔案路徑、程式識別字、schema 欄位名與引用原文逐字保留。

---
### Requirement: cash-apply 任務迴圈的阻塞分類

`cash-apply` 在 task loop 遇到實作阻塞時，SHALL 依「觀察到的 contract 是否改變」把阻塞分類為兩類並採取對應處置：機制替換（contract 不變）記一筆 Implementation Notes Protocol 的 `deviation` 條目後繼續，contract／範圍／行為變更則暫停並引導使用者前往 `cash-ingest`。此分類的暫停判準 MUST 逐字內嵌 Fix-loop design circuit breaker 觸發條件的英文片語 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`，使 task-loop 與 review-loop 對「何謂真正的 design 變更」使用同一個可稽核的邊界字串。兩分支 MUST 互斥：當機制替換分支的條件全部成立時走機制替換分支，「在多個都保留 contract 的替代手段之間選一個」的內部選擇 SHALL 以記 `deviation` 解決，不觸發暫停分支。兩個分類分支 MUST 優先於通用 error／blocker fallback；該 fallback MUST 僅處理未被 blocker triage 涵蓋的其他錯誤或阻塞。此 requirement 適用於 `cash-apply` 的兩個變體（`.claude` 與 `.agents`）。

#### Scenario: 機制替換且 contract 不變則記 deviation 後繼續

- **WHEN** 某個 task 的阻塞是「原設計指定的達成手段在目標平台或現實不可行」
- **AND** 要交付的觀察行為、interface／資料形狀、失敗模式與驗收標準都不變
- **AND** 替代手段不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`
- **THEN** `cash-apply` 依 Implementation Notes Protocol 記一筆 `類別：deviation` 條目
- **AND** 繼續實作該 task，不暫停，也不要求 `cash-ingest`

#### Scenario: contract、範圍或行為變更則暫停並導向 ingest

- **WHEN** 某個 task 的阻塞改變了要交付的觀察行為、範圍或使用者可見的取捨
- **THEN** `cash-apply` 暫停並報告該 blocker
- **AND** 引導使用者前往 `cash-ingest`

#### Scenario: 解答可能改變 contract 的 open question 則暫停

- **WHEN** 某個 task 存在其解答可能改變 contract 或範圍、需要使用者決定的 open question
- **THEN** `cash-apply` 暫停並引導使用者前往 `cash-ingest`

#### Scenario: 替代手段需要未定義的設計機制則暫停

- **WHEN** 某個 task 的替代手段需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`
- **THEN** `cash-apply` 走暫停分支而非繼續分支
- **AND** 引導使用者前往 `cash-ingest`

#### Scenario: 保留 contract 的內部手段選擇不觸發暫停

- **WHEN** 機制替換分支的全部條件成立
- **AND** 在多個都保留 contract 的替代手段之間存在需要選擇的內部問題
- **THEN** `cash-apply` 走機制替換分支，以記 `deviation` 解決該選擇
- **AND** 不因該內部選擇而暫停

#### Scenario: 兩個變體保持對等

- **WHEN** 比較 `.claude/skills/cash-apply/SKILL.md` 與 `.agents/skills/cash-apply/SKILL.md` 的阻塞分類段落
- **THEN** 兩者在 invocation 前綴（`/cash-` 與 `$cash-`）正規化後 MUST 完全相同

## Cash-owned artifact fallback

- 使用者直接給 change 名稱 → 直接讀 `openspec/changes/<name>/` 底下的 artifacts；找不到時，先以 `git rev-parse --show-toplevel` 解析root，再執行該root下 `.cash-skills/bin/cash list --parked --json`
- 問程式碼或需求相關的問題 → 先使用 `.cash-skills/bin/cash search "<query>" --limit 10 --json`，合法zero-result再以 Grep／Read 搜尋 `openspec/specs/` 與程式碼

## Cash CLI 啟動信任模式

- `.cash-skills/manifest.tsv` 存在時，clone／pull 後直接使用 project-local `.cash-skills/bin/cash`；舊的 `.cash-skills/receipt.tsv` 不具權威且不會遮蔽 manifest。manifest 存在但為 invalid manifest 時 MUST fail closed，不得 fallback 到 receipt，也不得執行 `--init-receipt`。
- 只有 `.cash-skills/manifest.tsv` 缺失的 receipt-based target 在 `.cash-skills/bin/cash` 以 `bootstrap_invalid` 失敗時，才引導使用者在專案根執行一次 `PYTHONPATH=.cash-skills/lib python3 -s -P -B -m cash_cli.installer --init-receipt`（需 Python 3.11+）；成功後回報 `initialized` 或 `current`，cash CLI 即可使用。`.cash-skills/receipt.tsv` 是 machine-local identity，不得提交或跨 clone 共用。
<!-- CASH:END -->
