# Cash Propose Review — Round 1

## Reviewer Findings

Round 1 為 unseeded run 的第一輪，因此所有通過 confidence filter 的 Critical 與 Warning 皆為 blocking，且不需標註 `disposition`。兩位 reviewer 的重複 finding 依 `location + summary` 合併。

### Critical

（無）

### Warning

1. `severity`: Warning／`confidence`: 99／`layer`: design／來源：Reviewer A 與 Reviewer B
   - `location`: `proposal.md` Impact、`tasks.md` 1.4、`iPhoneLocationMoveTunnelHelper/Acceptance/prepare-endpoint-timeout.py`
   - `summary`: 版本化 runtime 路徑未傳播到固定 acceptance fixture；timeout fixture 仍硬編碼舊 `TunnelRuntime/current`，且未列入 Impact 或 task delivery。
   - `recommendation`: 將 fixture 納入 scope，改用版本化 runtime path，並加入 residual scan。

2. `severity`: Warning／`confidence`: 99／`layer`: design／來源：Reviewer B
   - `location`: `design.md` Decision 5／Implementation Contract 10、`tasks.md` 1.5
   - `summary`: production verification 只執行 `positive-start`；cleanup、reconcile、timeout與 tamper cases 沒有被單一可執行 gate實際執行及比對 typed result／snapshot。
   - `recommendation`: 建立固定 production suite runner，依 manifest執行所有 required cases、比對 typed error及 before／after process snapshot，並完整保存 evidence。

3. `severity`: Warning／`confidence`: 99／`layer`: design／來源：Reviewer A 與 Reviewer B
   - `location`: delta spec「macOS 27 連接 iOS 27 USB iPhone」、`design.md` Decision 5、`tasks.md` 1.5、`iPhoneLocationMove/App/iPhoneLocationMoveApp.swift`
   - `summary`: requirement 承諾 tunnel後完成 DVT preparation並發布 ready session，但既有 `positive-start` 只直接呼叫 `LiveTunnelClient`，無法證明實際 device-session ready。
   - `recommendation`: 新增固定 `device-session-ready` production case，從 signed App 的實際 preparation path執行至 DVT/device session ready並保存狀態。

4. `severity`: Warning／`confidence`: 88／`layer`: design／來源：Reviewer B
   - `location`: `design.md` Decisions 2–3／Implementation Contract 1、7；`tasks.md` 1.3、1.5；`README.md`
   - `summary`: 對所有支援 host 強制 native 且禁止 fallback，但專案仍宣告 macOS 13+／iOS 17+；唯一真實證據只有 macOS 27 + iOS 27，可能使既有支援矩陣退化。
   - `recommendation`: 建立明確 host policy；只在 measured macOS 27+ 啟用 native，較早受支援 macOS 保留既有 classic transport，並測試兩個固定分支且禁止失敗後切換。

5. `severity`: Warning／`confidence`: 91／`layer`: design／來源：Reviewer A
   - `location`: delta spec「升級時存在舊版 sealed runtime」、`design.md` Implementation Contract 5、`tasks.md` 1.3
   - `summary`: requirement 要求舊 runtime 不被執行、覆寫或信任，但 task 只籠統要求 versioned runtime assertion，無法偵測實作先刪除舊 `current`。
   - `recommendation`: contract test 預先建立含 sentinel 的 legacy sibling，斷言只執行 pinned-version executable，且舊內容與 metadata保持不變。

### Suggestion

（無）

## Rating

- post-filter cumulative blocking set Critical count: 0
- post-filter cumulative blocking set Warning count: 5
- 非 blocking triaged finding count: 0
- `critical_gap`: false
- `round_type`: full

rationale：五筆合併後 findings 均有直接 artifact 或 repository code證據且 confidence ≥ 80，全部進入第一輪 cumulative blocking set。所有 finding 已完成 artifact fix，但尚未經後續 reviewer確認，因此本輪不得判為 `passed`。

## Fix Actions

pre-round mechanical self-check：comment／separator、requirement title identity、numeric claim、identifier cross-grep與 `git diff --check` 均通過；所有 open signals 都沒有 `check` frontmatter，不需執行 signal command。

- finding 1：修改 `proposal.md` 與 `tasks.md`，將 `prepare-endpoint-timeout.py` 納入 Impact／delivery，要求所有 acceptance assets改用 `pymobiledevice3-11.13.0`，並加入舊 active path residual scan。
- finding 2：修改 `proposal.md`、`design.md` 與 `tasks.md`，新增固定、無任意參數的 `run-production-acceptance.sh`；要求依 `cases.json` 執行所有 required cases，negative cases比對指定 `errorCode`，cleanup cases比對 before／after process snapshot，缺證據整體 fail。
- finding 3：修改 `proposal.md`、`design.md`、delta spec與 `tasks.md`，新增 `device-session-ready` case；將 App runner、`cases.json` 與 `AppLifecycleTests.swift` 納入 Impact／delivery，明定必須走實際 DVT preparation至 ready session。
- finding 4：修改 `proposal.md`、`design.md`、delta spec與 `tasks.md`，定義單次 host policy：macOS 27+ 使用 native，macOS 13–26 維持 classic；兩者都使用固定 command，且 process failure後不得切換。設計補入 upstream iOS 17+ tunnel support matrix來源。
- finding 5：修改 `design.md`、delta spec與 `tasks.md`，要求以含 sentinel 的舊 `current` sibling驗證只執行版本化 runtime，且 legacy內容與 metadata完全不變。
- post-fix：`cash analyze` 的 Coverage／Consistency／Gaps 均為 Clean，Ambiguity 只剩 9 筆非阻塞 Example suggestions；`cash validate` 回報 `valid:true`；機械檢查與 `git diff --check` 通過。
- 本輪只修改 change directory內 artifacts，無 change外路徑需執行 `cash touched record`。

## Decision

next_round
