# Cash Propose Review — Round 1

## Reviewer Findings

### Critical

None.

### Warning

1. `severity`: Warning；`confidence`: 100；`layer`: design；`location`: `design.md`「Decisions」第 4 點與「Implementation Contract」第 5 點、`tasks.md` 1.1 與 2.2；`summary`: 原規劃只驗證 shared store reference 的 `simulationStore` 變為非 `nil`，即使未使用 `@ObservedObject` 也會通過，無法證明同一 SwiftUI hierarchy 由 disconnected controls 切換至 connected controls；`recommendation`: 使用原生 hosting hierarchy 與穩定 accessibility identifier，直接驗證 setup ready 後的 view invalidation；reviewer source: Reviewer A — Adherence、Reviewer B — Quality。

### Suggestion

None.

## Rating

- cumulative blocking Critical: 0
- cumulative blocking Warning: 1
- non-blocking triaged finding: 0
- `critical_gap`: false
- `round_type`: full
- 兩位 reviewer 獨立確認相同的測試 seam 缺口；該 Warning 以 100 confidence 通過 filter，第一輪屬 blocking，必須修正並進入下一輪驗證。

## Fix Actions

- 修改 `proposal.md`：把原生 `NSHostingView` regression test、穩定 accessibility identifier 與新增／修改檔案納入 solution 及 structured scope。
- 修改 `design.md`：要求測試在同一 hosting view 上驗證 disconnected → connected branch，明定兩個互斥 identifier、有界 main-run-loop 更新與 window cleanup；此測試在缺少 `@ObservedObject` 或保存 snapshot 時必須失敗。
- 修改 `tasks.md`：改為先建立 `ContentViewTests.swift` hosting regression test，再實作 observation container 與 accessibility identifiers，最後執行 targeted／完整 tests。
- Post-fix mechanical self-check：spec annotation／separator、identifier propagation 與 structured paths 均一致；重新執行 `cash validate` 通過，未需額外修正。

## Decision

next_round
