# Review 經驗教訓（signals）

開發過程中 review 反覆抓到的問題型態，共 73 條。每條記錄「規則」與在各 change 出現的情形；`出現次數` 越高代表越容易再犯，新的設計或 review 時可當 checklist 使用。設計文件（[`designs/`](designs/)）中提到的 signal 名稱即為此處的 id。

## 索引

| id | 次數 | 摘要 |
|---|---|---|
| [`artifact-claimed-coverage-exceeds-oracle`](#artifact-claimed-coverage-exceeds-oracle) | 5 | Artifact 宣稱的測試涵蓋大於實際可證偽範圍 |
| [`fix-propagation-misses-one-artifact`](#fix-propagation-misses-one-artifact) | 4 | 修復只傳播到部分 artifact |
| [`ui-observation-test-no-invalidation`](#ui-observation-test-no-invalidation) | 4 | UI observation regression test 未驗證 view invalidation |
| [`privileged-boundary-no-real-acceptance`](#privileged-boundary-no-real-acceptance) | 3 | Privileged boundary 只有 unit contract test |
| [`privileged-process-lease-cleanup`](#privileged-process-lease-cleanup) | 3 | Privileged process 缺少 lease 與 crash cleanup |
| [`requirement-scope-exceeds-implementation`](#requirement-scope-exceeds-implementation) | 3 | Requirement 宣告的涵蓋範圍超過實作 |
| [`acceptance-environment-precondition-mismatch`](#acceptance-environment-precondition-mismatch) | 2 | Acceptance environment 無法滿足測試前提 |
| [`added-delta-contradicts-master-requirement`](#added-delta-contradicts-master-requirement) | 2 | ADDED delta 行為與既有 master requirement 衝突 |
| [`annotation-update-camera-effect-replay`](#annotation-update-camera-effect-replay) | 2 | Annotation update 重播既有 camera effect |
| [`async-request-cancellation-generation-replacement`](#async-request-cancellation-generation-replacement) | 2 | Async request replacement 未完成舊 ownership |
| [`camera-effect-gate-no-boundary-test`](#camera-effect-gate-no-boundary-test) | 2 | Camera effect gate 缺少直接 boundary test |
| [`privileged-package-trust-gate-incomplete`](#privileged-package-trust-gate-incomplete) | 2 | Privileged package trust gate 未驗證實際雙向 identity |
| [`privileged-runtime-trust-anchor`](#privileged-runtime-trust-anchor) | 2 | Privileged runtime 缺少不可替換的 trust anchor |
| [`shell-contract-scenario-no-test-task`](#shell-contract-scenario-no-test-task) | 2 | Shell public contract scenario 沒有 backing test task |
| [`spec-scenario-no-view-test-task`](#spec-scenario-no-view-test-task) | 2 | Spec 的 view 層 scenario 與 Example 沒有測試 task |
| [`swiftui-sibling-observation-boundary`](#swiftui-sibling-observation-boundary) | 2 | SwiftUI sibling observation 未更新共同輸入 |
| [`transport-failure-state-unspecified`](#transport-failure-state-unspecified) | 2 | 執行中 transport failure 沒有狀態轉移 |
| [`acceptance-negative-case-error-oracle`](#acceptance-negative-case-error-oracle) | 1 | Negative acceptance case 未驗證指定失敗原因 |
| [`actor-reentrant-recovery-generation-gate`](#actor-reentrant-recovery-generation-gate) | 1 | Actor reentrant recovery 缺少 generation gate |
| [`async-preview-stale-response`](#async-preview-stale-response) | 1 | Async preview response 未隨 ownership 變更失效 |
| [`async-test-mutable-baseline-race`](#async-test-mutable-baseline-race) | 1 | Async test 使用可變 reference 作為比較基準 |
| [`async-update-backpressure-barrier`](#async-update-backpressure-barrier) | 1 | Async update 缺少 backpressure 與實體狀態 barrier |
| [`build-version-setting-no-metadata-consumer`](#build-version-setting-no-metadata-consumer) | 1 | Build version setting 沒有產物 metadata consumer |
| [`camera-effect-precedence-overlay-shadowing`](#camera-effect-precedence-overlay-shadowing) | 1 | 既有 overlay 存在遮蔽新的 camera intent |
| [`candidate-transport-identity-lifecycle-order`](#candidate-transport-identity-lifecycle-order) | 1 | Candidate transport identity lifecycle 順序矛盾 |
| [`command-change-stale-doc-pattern`](#command-change-stale-doc-pattern) | 1 | 改變固定 command 後，文件中的 process 比對字串未同步 |
| [`crash-relaunch-cleanup-ownership`](#crash-relaunch-cleanup-ownership) | 1 | Crash 後沒有持久 cleanup ownership |
| [`design-build-tooling-claim-unverified`](#design-build-tooling-claim-unverified) | 1 | Design 對 build 工具鏈的 claim 未經 repo 核實 |
| [`design-delivery-path-misses-member-file`](#design-delivery-path-misses-member-file) | 1 | Design 指定的成員實際定義在未列入 Impact 的檔案 |
| [`design-mechanism-statement-conflict`](#design-mechanism-statement-conflict) | 1 | Design 內同一機制的敘述互斥 |
| [`design-risk-premise-unverified`](#design-risk-premise-unverified) | 1 | Design 風險段落的事實前提未經核實 |
| [`device-switch-cleanup-transaction`](#device-switch-cleanup-transaction) | 1 | Active device switch 缺少 cleanup transaction |
| [`diagnostic-sensitive-detail-no-redaction`](#diagnostic-sensitive-detail-no-redaction) | 1 | Diagnostic detail 沒有敏感值 redaction |
| [`dmg-packaging-contract-test-incomplete`](#dmg-packaging-contract-test-incomplete) | 1 | DMG contract test 未驗證 staging 內容與 replacement boundary |
| [`error-classification-misses-raw-error-string`](#error-classification-misses-raw-error-string) | 1 | 錯誤分類關鍵字未涵蓋底層原始錯誤字串 |
| [`fix-action-claimed-but-not-written`](#fix-action-claimed-but-not-written) | 1 | Fix Action 宣稱已修但檔案未變更 |
| [`generated-user-state-scope-drift`](#generated-user-state-scope-drift) | 1 | Tool execution 夾帶個人 user-state binary diff |
| [`helper-contract-deliverables-no-task`](#helper-contract-deliverables-no-task) | 1 | Helper contract deliverables 沒有 task |
| [`host-support-matrix-transport-regression`](#host-support-matrix-transport-regression) | 1 | 新 transport 無條件取代既有支援矩陣 |
| [`legacy-runtime-preservation-no-oracle`](#legacy-runtime-preservation-no-oracle) | 1 | 版本化 runtime 升級未驗證舊內容保持不變 |
| [`mode-replacement-failure-state`](#mode-replacement-failure-state) | 1 | Mode replacement 第一個 mutation 失敗時狀態未定義 |
| [`modified-delta-omits-master-scenario`](#modified-delta-omits-master-scenario) | 1 | MODIFIED delta 漏抄 master 的既有 scenario |
| [`multi-stream-output-spliced-into-one-message`](#multi-stream-output-spliced-into-one-message) | 1 | 多個輸出串流被接合成單一訊息 |
| [`mutation-terminal-state-type-split`](#mutation-terminal-state-type-split) | 1 | Mutation terminal state 未依操作類型分流 |
| [`numeric-update-cadence-no-test`](#numeric-update-cadence-no-test) | 1 | 數值 update cadence 沒有可控制時間的測試 |
| [`preview-camera-coordinate-dedup`](#preview-camera-coordinate-dedup) | 1 | Preview camera effect 以 coordinate 去重 |
| [`preview-camera-intent-stale-clear`](#preview-camera-intent-stale-clear) | 1 | Preview 清除未同步失效 camera intent |
| [`preview-camera-intent-transition-no-test`](#preview-camera-intent-transition-no-test) | 1 | Preview camera intent transition 沒有 owner-level test |
| [`privileged-active-lease-stale-retry`](#privileged-active-lease-stale-retry) | 1 | Active privileged lease retry 未驗證 process 存活 |
| [`privileged-caller-identity-not-audit-token`](#privileged-caller-identity-not-audit-token) | 1 | Privileged caller trust 未綁定 connection audit token |
| [`privileged-helper-restart-orphan-cleanup`](#privileged-helper-restart-orphan-cleanup) | 1 | Privileged helper restart 可能遺留 root child |
| [`privileged-startup-process-untracked`](#privileged-startup-process-untracked) | 1 | Privileged process 在啟動完成前沒有可取消 ownership |
| [`programmatic-camera-interaction-misclassification`](#programmatic-camera-interaction-misclassification) | 1 | Programmatic camera update 誤判為使用者操作 |
| [`reconnect-partial-failure-identity-drift`](#reconnect-partial-failure-identity-drift) | 1 | Reconnect 中途失敗留下半套 session 與 stale generation |
| [`recovery-cancellation-transport-identity-collision`](#recovery-cancellation-transport-identity-collision) | 1 | Recovery cancellation 與 transport identity 共用 generation |
| [`recovery-ownership-event-matrix-gap`](#recovery-ownership-event-matrix-gap) | 1 | Recovery ownership event matrix 缺少直接邊界測試 |
| [`recursive-isolation-oracle-incomplete`](#recursive-isolation-oracle-incomplete) | 1 | Isolation test 使用淺層 directory stat 作為 oracle |
| [`repository-build-output-not-ignored`](#repository-build-output-not-ignored) | 1 | Repository-local build output 未加入 ignore |
| [`route-terminal-state-transitions`](#route-terminal-state-transitions) | 1 | Route terminal state 缺少後續轉移 |
| [`spec-delta-internal-requirement-conflict`](#spec-delta-internal-requirement-conflict) | 1 | 同一份 delta 內兩條 requirement 對同一輸入互相牴觸 |
| [`stale-view-action-cancels-current-request`](#stale-view-action-cancels-current-request) | 1 | Stale view action 取消 current async request |
| [`test-marker-keyboard-focus-leak`](#test-marker-keyboard-focus-leak) | 1 | Test marker 仍可取得鍵盤 focus |
| [`test-marker-production-control-identity-collision`](#test-marker-production-control-identity-collision) | 1 | Test marker 與 production control identity 碰撞 |
| [`test-seam-bypasses-confirmation`](#test-seam-bypasses-confirmation) | 1 | 測試 seam 繞過 production 確認邊界 |
| [`test-task-requires-missing-seam`](#test-task-requires-missing-seam) | 1 | Task 規劃的測試需要不存在的注入 seam |
| [`user-visible-device-selection-no-task`](#user-visible-device-selection-no-task) | 1 | 使用者可見的裝置選擇沒有 backing task |
| [`view-cancellation-oracle-no-spy`](#view-cancellation-oracle-no-spy) | 1 | View cancellation regression 沒有觀察 production path |
| [`view-layout-oracle-incomplete-state-matrix`](#view-layout-oracle-incomplete-state-matrix) | 1 | View layout oracle 的狀態矩陣不完整 |
| [`view-layout-oracle-misses-status-region`](#view-layout-oracle-misses-status-region) | 1 | View layout oracle 漏驗狀態區域 |
| [`view-layout-oracle-partial-visibility`](#view-layout-oracle-partial-visibility) | 1 | View layout oracle 只驗證部分可見 |
| [`view-lifecycle-request-deduplication`](#view-lifecycle-request-deduplication) | 1 | View lifecycle 無法保存 request 去重 ownership |
| [`xcode-test-file-target-membership`](#xcode-test-file-target-membership) | 1 | 新增 Xcode test file 未納入 target membership |
| [`xcodegen-regeneration-scope-drift`](#xcodegen-regeneration-scope-drift) | 1 | XcodeGen regeneration 夾帶非必要 scope drift |

## artifact-claimed-coverage-exceeds-oracle

**Artifact 宣稱的測試涵蓋大於實際可證偽範圍**　出現 5 次（2026-08-29 ～ 2026-08-29）

tasks 的 `success`／`red` 與 design 的測試清單所宣稱涵蓋的規則，必須是把該規則改壞後會有測試失敗的規則。單行 fixture 無法證偽「取最後一個」語意、不含對立標記的輸入無法證偽分類優先序、走測試專用接縫的斷言無法證偽 production 路徑、位於結構切割之外的內容無法證偽雜訊過濾規則。驗收敘述寫下之前，應以刻意破壞該規則的實驗確認至少一個案例會失敗。

**出現紀錄**：

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — 提案審查第 1 輪：task 1.5 宣稱分類順序由既有測試涵蓋，但該路徑住在 private actor 內、既有測試全走 fake boundary。
- 2026-08-29 — Round 3：task 1.5 的 `red` 宣稱分支對調會被抓到，但無任何 fixture 同時含鎖定與授權標記。
- 2026-08-29 — Round 4：`lastMeaningfulLine` 的「取最後一個」語意零覆蓋，`.last` 改 `.first` 全套仍綠。
- 2026-08-29 — Round 6：production 端截斷走 `classify` 而唯一截斷測試走測試接縫 `summarize`；五條雜訊規則中三條因位於方框結構切割之外而零覆蓋。

## fix-propagation-misses-one-artifact

**修復只傳播到部分 artifact**　出現 4 次（2026-08-29 ～ 2026-09-17）

跨 artifact 的行為敘述修改後，必須把該概念在 proposal、design Decisions、design Implementation Contract、tasks 敘述與 success、spec requirement 與 scenario、程式碼與測試逐一同步；其中 proposal 最常被遺漏。殘留掃描的 pattern 必須短且不含可變修飾語——以完整句子為 pattern 時，措辭的細微差異會讓掃描回報 0 而漏抓。

**出現紀錄**：

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — 提案審查第 3 輪：分類同時檢視兩個串流的修改漏掉 `proposal.md`。
- 2026-08-29 — Round 4：改為串流優先序後 design Decisions、tasks 1.5 與 spec MODIFIED 三處仍保留舊的全域宣稱。
- 2026-08-29 — Round 5：改回標記優先後 `proposal.md` 再次成為唯一漏掉的 artifact；殘留掃描用完整句子當 pattern 而漏抓。
- 2026-09-05 — `auto-reconnect-after-usb-replug` — 提案審查第 2 輪：round 1 把 `reconnecting` 改為不持有 cleanup ownership時同步了 design、spec、tasks，漏掉 proposal.md Proposed Solution 一處。
- 2026-09-17 — `fix-ios-27-usb-tunnel` — 提案審查第 1 輪：版本化 tunnel runtime 已同步到設計與文件，但漏掉硬編碼舊 `TunnelRuntime/current` 的 production timeout fixture及其 delivery scope。

## ui-observation-test-no-invalidation

**UI observation regression test 未驗證 view invalidation**　出現 4 次（2026-07-27 ～ 2026-08-27）

修正 reactive UI stale state 時，測試必須觀察同一 rendered hierarchy 在 publisher 更新後切換輸出；只讀 shared reference 的最新 property 不能證明 observation wrapper 觸發 view 重算，可能讓原 regression 在測試全綠時持續存在。

**出現紀錄**：

- 2026-07-27 — `fix-stale-simulation-controls` — 提案審查第 1 輪：原測試只驗證 shared `DeviceSetupStore.simulationStore` 變為非 `nil`，即使缺少 `@ObservedObject` 也會通過。
- 2026-07-27 — `fix-map-sidebar-control-layout` — 提案審查第 1 輪：原布局測試規劃為每種 state 重建 fixture，無法證明同一 rendered hierarchy 在 `SimulationStore` publisher 更新後重新 layout。
- 2026-07-27 — `fix-map-sidebar-control-layout` — 實作審查第 2 輪：paused 測試只等待 model phase，未等待同一 hosting hierarchy materialize resume probe，造成同步 flake。
- 2026-08-27 — `add-favorites` — 實作審查第 6 輪：收藏 toggle 測試未直接驗證同一 rendered hierarchy 的可見 title 變化。

## privileged-boundary-no-real-acceptance

**Privileged boundary 只有 unit contract test**　出現 3 次（2026-07-26 ～ 2026-09-17）

audit token、root ownership、daemon cleanup、runtime tamper 與 uninstall 行為需要隔離的實際 privileged acceptance；fake XPC unit tests 無法證明部署後 boundary。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 1 輪：privileged helper 最初缺少需管理員核准的真實環境 gate。
- 2026-07-27 — `add-macos-location-simulator` — 實作審查第 1 輪：task 7.3 將 user-space fake harness 與正向 production smoke 合併宣稱完整 privileged adversarial acceptance，未在真實 XPC／SMJobBless boundary驗證負向案例。
- 2026-09-17 — `fix-ios-27-usb-tunnel` — 提案審查第 1 輪–2：production gate 最初只執行 positive tunnel start，補齊 real XPC cases後又漏掉 master contract要求的 uninstall final cleanup。

## privileged-process-lease-cleanup

**Privileged process 缺少 lease 與 crash cleanup**　出現 3 次（2026-07-26 ～ 2026-07-27）

長時間 root process 必須有 caller-bound lease、idempotent start、owner-death cleanup、遺失 reply recovery 與 startup reconcile，不能只依顯式 stop。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 1 輪：tunnel 最初沒有 App crash、XPC invalidation 或 duplicate start 回收 contract。
- 2026-07-27 — `add-macos-location-simulator` — 實作審查第 1 輪：production startup沒有在start前執行fail-closed reconcile，relaunch可能沿用或疊加stale caller lease。
- 2026-07-27 — `add-macos-location-simulator` — 實作審查第 2 輪：一般 preparation已修正 reconcile，但 transport recovery的 replacement start一度漏掉相同 fail-closed ordering。

## requirement-scope-exceeds-implementation

**Requirement 宣告的涵蓋範圍超過實作**　出現 3 次（2026-08-29 ～ 2026-09-17）

requirement 列舉階段、輸入來源或條件時，必須逐一對照實作的實際覆蓋路徑。宣稱涵蓋七個 prerequisite 階段但分類只掛在其中四個走同一子行程入口的階段、宣稱檢視整個輸出串流但實作只檢視收斂後的單一摘要行，都會讓 archive 後的 master spec 對未實作的行為做出承諾。

**出現紀錄**：

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — 提案審查第 1 輪：MODIFIED requirement 宣稱鎖定分類涵蓋七個階段，但 tunnel 與 DVT 走 privileged helper 與 helper 程序而不做鎖定判定。
- 2026-08-29 — Round 3：spec 宣稱分類同時檢視兩個串流，實作只檢視各串流雜訊過濾後的單一摘要行。
- 2026-09-17 — `fix-ios-27-usb-tunnel` — 提案審查第 1 輪：spec 承諾 tunnel後完成 DVT preparation並發布 ready session，但原 task只驗證 `LiveTunnelClient` 的 tunnel start/status/stop。

## acceptance-environment-precondition-mismatch

**Acceptance environment 無法滿足測試前提**　出現 2 次（2026-07-26 ～ 2026-07-27）

acceptance task 宣告的實體資源必須足以執行列出的行為；單裝置環境不能驗證需要第二台可選裝置的 switch 流程。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 4 輪：單 iPhone acceptance 一度要求 active-device switch failure。
- 2026-07-27 — `recover-dropped-device-tunnel` — 提案審查第 2 輪：proposal一度把實體強制中斷列為必然交付，但design與tasks允許環境不安全時不執行。

## added-delta-contradicts-master-requirement

**ADDED delta 行為與既有 master requirement 衝突**　出現 2 次（2026-07-27 ～ 2026-09-05）

新 delta 引入的行為若落在既有 master requirement 的管轄範圍（例如解除該 requirement 的禁止條款），必須以 MODIFIED requirement 逐字承接並明文授權例外，不能只寫 ADDED requirement；否則 archive 後兩份 master 條文互相矛盾。

**出現紀錄**：

- 2026-07-27 — `add-mac-recenter-and-workspace-reset` — 提案審查第 1 輪：工作區重置的「重新武裝初始置中」與 master「初始置中不得覆寫使用者地圖脈絡」的「不得重新取得 camera ownership」衝突，delta 最初未 MODIFIED 該 requirement。
- 2026-09-05 — `auto-reconnect-after-usb-replug` — 提案審查第 1 輪：ADDED「未偵測 USB 中斷後的自動重新準備」讓第一個 mutation 失敗後仍顯示 active，與 master「模擬模式互斥與安全取代」「單點定位模式」的「第一個 mutation 失敗 SHALL interrupted」衝突，最初未 MODIFIED 該兩個 requirement。

## annotation-update-camera-effect-replay

**Annotation update 重播既有 camera effect**　出現 2 次（2026-07-27 ～ 2026-07-30）

Map render state 與 programmatic camera effect 必須分離；annotation 或 overlay redraw 不得從既有 route／preview snapshot 再次推導並重播 camera 操作，camera effect 應以可消耗 identity 套用一次。

**出現紀錄**：

- 2026-07-27 — `show-mac-location-on-device-ready` — 提案審查第 1 輪：Mac marker 更新最初會讓既有 route 再次執行 `setVisibleMapRect`。
- 2026-07-30 — `preserve-map-camera-on-click` — 提案審查第 2 輪：route precedence 修正最初未消耗同輪 preview identity，下一次 annotation／overlay redraw 可能延遲重播 preview center。

## async-request-cancellation-generation-replacement

**Async request replacement 未完成舊 ownership**　出現 2 次（2026-07-27 ～ 2026-07-27）

以 generation 取代單一 in-flight async request 時，必須先讓舊 request 經 cancellation terminal path 完成並清除 ownership，再啟動最新 generation；只丟棄 stale response 仍可能讓舊 continuation 阻塞新要求。

**出現紀錄**：

- 2026-07-27 — `show-mac-location-on-device-ready` — 提案審查第 1 輪：舊 Core Location continuation 最初可能讓 reconnect generation 收到 concurrent-request error。
- 2026-07-27 — `show-mac-location-on-device-ready` — 實作審查第 1 輪：pre-cancelled Core Location task 一度繞過 typed cancellation terminal mapping。

## camera-effect-gate-no-boundary-test

**Camera effect gate 缺少直接 boundary test**　出現 2 次（2026-07-27 ～ 2026-07-30）

以 identity 或 ownership 控制 programmatic camera effect 時，測試必須直接執行 effect gate；只驗證上游 model state 無法證明 redraw 不重播 camera，也無法證明 programmatic 與 manual interaction 的分類正確。

**出現紀錄**：

- 2026-07-27 — `show-mac-location-on-device-ready` — 實作審查第 1 輪：初版測試只驗證 route identity model state，未執行 canvas camera effect gate。
- 2026-07-30 — `preserve-map-camera-on-click` — 提案審查第 1 輪：camera isolation contract 禁止 `setCenter`，但原 test spy 未計數該 mutation，無法完整驗證 effect boundary。

## privileged-package-trust-gate-incomplete

**Privileged package trust gate 未驗證實際雙向 identity**　出現 2 次（2026-07-27 ～ 2026-07-27）

包含 privileged helper 的 package gate 必須對實際 signed App 與 embedded helper 驗證固定 identifiers、固定 Team 與雙向 authorization requirements；只比較兩者 Team 相同或只讀 repository source plist，可能讓無法通過 production authorization 的產物被誤判成功。

**出現紀錄**：

- 2026-07-27 — `add-package-app-script` — 提案審查第 1、2 輪：簽署 gate 最初只比較相同 Team，修正後仍一度以 source helper plist 代替 built embedded helper metadata。
- 2026-07-27 — `add-package-app-script` — 實作審查第 1 輪：實作已讀 built metadata，但初版 regression fixture 沒有同時提供正確 source plist，未直接防止未來 source fallback 掩蓋 embedded drift。

## privileged-runtime-trust-anchor

**Privileged runtime 缺少不可替換的 trust anchor**　出現 2 次（2026-07-26 ～ 2026-07-27）

privileged process 安裝或執行 runtime 時，只有 hash、owner 或 mode 不足以證明 payload provenance；trust anchor 必須固定在已驗證簽章的 boundary，並防止 payload 與 manifest 同時替換。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 1 輪：root-owned tunnel runtime 最初未定義 code-signature provenance 與 immutable digest trust anchor。
- 2026-07-27 — `add-macos-location-simulator` — 實作審查第 1 輪：embedded digest固定wheelhouse與manifest，但未固定`pip --target`產生的實際runtime tree，啟動前無法拒絕額外generated內容。

## shell-contract-scenario-no-test-task

**Shell public contract scenario 沒有 backing test task**　出現 2 次（2026-07-27 ～ 2026-07-27）

shell 入口的 path resolution、short aliases 與 fail-before-destructive-action 等 public contract 必須在 tasks 中有對應 deterministic cases；只規劃一般成功／失敗 command shims，無法證明非 root current directory、含空白路徑或 marker 缺失時的安全行為。

**出現紀錄**：

- 2026-07-27 — `add-package-app-script` — 提案審查第 1 輪：初版 tasks 未明列非 root cwd、含空白 fixture path、marker fail-before-clean 與 `-h`／`-v` aliases。
- 2026-07-27 — `add-package-app-script` — 實作審查第 1 輪：contract suite 一度只直接驗證 `-v` 成功路徑，沒有對應的 `--version` 成功案例。

## spec-scenario-no-view-test-task

**Spec 的 view 層 scenario 與 Example 沒有測試 task**　出現 2 次（2026-07-27 ～ 2026-08-27）

spec scenario 或 Example 涉及 view 層可觀察行為（toggle 歸位、按鈕 disabled、警語分支、失敗顯示保留）時，tasks 不能只列 model 層測試；必須有對應 view 層測試 task（hosting-view 模式）或把行為抽成可測純函式，否則 Example 無法驗收。

**出現紀錄**：

- 2026-07-27 — `add-mac-recenter-and-workspace-reset` — 提案審查第 1 輪：Example「往返循環關閉」與警語分支、busy disabled、clear 失敗不掩蓋等 scenario 最初無任何對應測試 task。
- 2026-08-27 — `add-favorites` — 實作審查第 6 輪：delete 後 preview／simulation 已驗證，但 map annotation 的 rendered boundary oracle 仍缺失。

## swiftui-sibling-observation-boundary

**SwiftUI sibling observation 未更新共同輸入**　出現 2 次（2026-07-27 ～ 2026-07-27）

當 sibling view 各自依賴同一個 `ObservableObject` 時，只在其中一個 subtree 觀察 object 不會保證父層重算另一個 sibling 的輸入；共同 state 衍生應由直接觀察該 object 的共同 shell 擁有。

**出現紀錄**：

- 2026-07-27 — `show-mac-location-on-device-ready` — 提案審查第 1 輪：ready generation 最初由未觀察 `DeviceSetupStore` 的 `ContentView` 衍生。
- 2026-07-27 — `add-mac-recenter-and-workspace-reset` — 提案審查第 1 輪：reset 需清空的 `message` 是 sibling `SimulationControls` 的 view-local `@State`，design 最初只上移 `roundTrip` 而漏掉它。

## transport-failure-state-unspecified

**執行中 transport failure 沒有狀態轉移**　出現 2 次（2026-07-26 ～ 2026-07-27）

active session 的 timeout、helper exit 或 tunnel death 必須停止 producer，標示外部狀態不確定並定義 recovery；typed error 本身不足以防止 UI 繼續顯示 running。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 1 輪：mid-route DVT failure 最初沒有進入 interrupted 的 contract。
- 2026-07-27 — `recover-dropped-device-tunnel` — 提案審查第 1 輪：新增 recovery success 例外時未同步修改既有 transport failure 立即 interrupted 的 normative contract。

## acceptance-negative-case-error-oracle

**Negative acceptance case 未驗證指定失敗原因**　出現 1 次（2026-07-27 ～ 2026-07-27）

負向 acceptance case不能把任意 error視為通過；runner與case manifest必須驗證該案例指定的 typed error，避免環境、授權或連線錯誤產生假陽性。

**出現紀錄**：

- 2026-07-27 — `add-macos-location-simulator` — 實作審查第 2 輪：endpoint timeout與runtime seal tamper runner一度接受任何 thrown error，且endpoint manifest code與實際 typed `timeout`不一致。

## actor-reentrant-recovery-generation-gate

**Actor reentrant recovery 缺少 generation gate**　出現 1 次（2026-07-27 ～ 2026-07-27）

跨多個 `await` 的 transport recovery transaction 必須在每個外部 side effect 前後重新驗證 captured logical generation 與 device identity；只在入口檢查會讓 disconnect、quit 或 reconnect 插入後的舊 recovery 建立資源或重播 stale mutation。

**出現紀錄**：

- 2026-07-27 — `recover-dropped-device-tunnel` — 提案審查第 1 輪：tunnel recovery 最初未在 status、stop、start、replay 與 commit 邊界重新驗證 session ownership。

## async-preview-stale-response

**Async preview response 未隨 ownership 變更失效**　出現 1 次（2026-07-26 ～ 2026-07-26）

search 或 directions response 必須綁定 query／endpoint generation；任何取代 preview ownership 的操作都要失效舊 request，而不只是送出新 query。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 1 輪：MapKit response 最初可能覆寫較新的 query 或 A／B；Round 4 進一步發現 map click path。

## async-test-mutable-baseline-race

**Async test 使用可變 reference 作為比較基準**　出現 1 次（2026-07-27 ～ 2026-07-27）

非同步測試若要比較更新前後狀態，必須在觸發更新前將基準值複製為不可變 snapshot；更新後再從同一個可變 reference讀取舊值會產生排程競態，使測試誤等下一次變化或偶發逾時。

**出現紀錄**：

- 2026-07-27 — `show-confirmed-iphone-route-marker` — 實作審查第 1 輪：rendered-hierarchy test在route tick後才從同一annotation instance讀取初始longitude，device completion若先更新該instance就會污染比較基準。

## async-update-backpressure-barrier

**Async update 缺少 backpressure 與實體狀態 barrier**　出現 1 次（2026-07-26 ～ 2026-07-26）

週期性 mutation 必須限制 in-flight 數、coalesce pending 值，並在 pause／clear 等操作確認外部實體狀態；只忽略 stale UI completion 不能阻止舊 mutation 影響裝置。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 1 輪：route tick 最初可能累積，pause 後舊座標仍可套用到 iPhone。

## build-version-setting-no-metadata-consumer

**Build version setting 沒有產物 metadata consumer**　出現 1 次（2026-07-27 ～ 2026-07-27）

打包流程宣稱以 build setting 覆寫版本時，實際產物的版本 metadata 必須引用該 setting，並在 build 後直接驗證；只把值傳給 build command 或用於檔名，不能證明交付 binary 的版本已更新。

**出現紀錄**：

- 2026-07-27 — `add-package-app-script` — 提案審查第 1 輪：`MARKETING_VERSION` 最初沒有 `CFBundleShortVersionString` consumer，版本只反映在 DMG 檔名。

## camera-effect-precedence-overlay-shadowing

**既有 overlay 存在遮蔽新的 camera intent**　出現 1 次（2026-07-30 ～ 2026-07-30）

Camera precedence必須依本輪是否實際套用effect判斷，不能只依annotation或overlay是否存在；已消耗identity對應的render物件不得永久遮蔽後續新的使用者camera intent。

**出現紀錄**：

- 2026-07-30 — `preserve-map-camera-on-click` — 提案審查第 1 輪：route overlay存在時原Coordinator永遠停在route分支，已消耗的route identity仍會遮蔽新的搜尋置中。

## candidate-transport-identity-lifecycle-order

**Candidate transport identity lifecycle 順序矛盾**　出現 1 次（2026-07-27 ～ 2026-07-27）

replacement transport在commit前必須使用transaction-scoped candidate identity驗證reply；identity只能在其所有組成資源實際取得後建立，candidate reply先形成local result，待ownership重驗證與atomic commit後才能發布logical success。

**出現紀錄**：

- 2026-07-27 — `recover-dropped-device-tunnel` — 提案審查第 3、4 輪：candidate replay一度被current-generation gate拒絕，且完整identity被描述為在DVT handle取得前建立。

## command-change-stale-doc-pattern

**改變固定 command 後，文件中的 process 比對字串未同步**　出現 1 次（2026-10-27 ～ 2026-10-27）

變更 helper 或子程序的固定 command／arguments 時，必須 grep 整個 repo（含 acceptance 手冊、runner、README）中比對舊 command 的 `pgrep`／regex／字串，並把這些檔案列入 proposal Impact 與 tasks delivery；否則清理或殘留檢查可能過期而產生假陰性。

**出現紀錄**：

- 2026-10-27 — `fix-ios-27-2-classic-tunnel` — 提案審查第 1 輪：helper 由 `remote start-tunnel --native` 改為 `lockdown start-tunnel`，但 `iPhoneLocationMoveTunnelHelper/Acceptance/PRODUCTION_ACCEPTANCE.md` 的 `pgrep` pattern 仍為 `pymobiledevice3.*remote.*tunnel`，且未列入 Impact。

## crash-relaunch-cleanup-ownership

**Crash 後沒有持久 cleanup ownership**　出現 1 次（2026-07-26 ～ 2026-07-26）

外部 mutation 可能在 App crash 或強制退出後殘留；若沒有持久記錄最小 device cleanup ownership，relaunch 無法保證在 ready 前對同一裝置 clear。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 4 輪：發現 tunnel reconcile 不等同裝置模擬狀態 recovery。

## design-build-tooling-claim-unverified

**Design 對 build 工具鏈的 claim 未經 repo 核實**　出現 1 次（2026-08-27 ～ 2026-08-27）

design 對專案檔管理或 build 工具鏈的 code-facing claim（例如「pbxproj 為手動維護」「無 generator」）必須先對 repo 實際狀態核實（generator spec、README 的建置流程、歷史 commit），不得憑目錄表象推斷；此類錯誤會直接誤導 tasks 的檔案註冊機制與 diff 驗收判準。

**出現紀錄**：

- 2026-08-27 — `add-favorites` — 提案審查第 1 輪：design 宣稱專案為手動維護的 `project.pbxproj`（無 XcodeGen），但 `iPhoneLocationMove/project.yml` 存在且 README 明定以 xcodegen generate 重新產生專案；tasks 的註冊與 diff 驗收判準因此需整組改寫。

## design-delivery-path-misses-member-file

**Design 指定的成員實際定義在未列入 Impact 的檔案**　出現 1 次（2026-09-05 ～ 2026-09-05）

design 要修改某型別的成員（例如 protocol conformance extension 的屬性或方法）時，必須 grep 該成員的實際定義位置，而不是假設它在型別主檔中；若成員定義在另一檔的 extension，且 design 又要求它讀取主檔的 `private` 狀態，proposal Impact 與 tasks delivery 都必須列入該檔並說明搬移或可見性調整，否則 apply 階段會遇到 Impact、tasks 與程式碼位置三者不符。

**出現紀錄**：

- 2026-09-05 — `auto-reconnect-after-usb-replug` — 提案審查第 4 輪：`hasActiveSimulation`／`stopForQuit` 定義在 `AppLifecycleCoordinator.swift` 的 `extension SimulationStore`，design 卻歸給 `SimulationStore.swift` 並要求讀取 `private var userActionTask`，Impact 與 tasks 未列該檔。

## design-mechanism-statement-conflict

**Design 內同一機制的敘述互斥**　出現 1 次（2026-07-27 ～ 2026-07-27）

design 對同一機制（對話框、state 擁有者、去重機制等）在 Decisions 與 Implementation Contract 間、或同一條 decision 前後，不得存在互斥敘述（例如同時宣稱「沿用既有 private 機制」與「由另一層自有 state 驅動」）；機制歸屬必須單一且可實作。

**出現紀錄**：

- 2026-07-27 — `add-mac-recenter-and-workspace-reset` — 提案審查第 1 輪：reset 確認對話框同時被寫成「沿用 `SimulationControls` private 的 `PendingMutation`」與「由 `LocationMapView` 自有 state 驅動、不共用」。

## design-risk-premise-unverified

**Design 風險段落的事實前提未經核實**　出現 1 次（2026-08-29 ～ 2026-08-29）

`## Risks / Trade-offs` 以「本次未寫入某處」「不引入新的某類路徑」作為不採取緩解措施的理由時，該前提必須先對實際程式碼路徑核實。前提為假時即使結論碰巧成立，錯誤的理由仍會誤導後續對同一議題的判斷。

**出現紀錄**：

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — 提案審查第 1 輪：design 以「未寫入持久診斷紀錄」為由不做敏感值遮蔽，但失敗 detail 會經 typed 失敗寫入 diagnostic metadata 並落地至使用者的 diagnostic.jsonl。

## device-switch-cleanup-transaction

**Active device switch 缺少 cleanup transaction**　出現 1 次（2026-07-26 ～ 2026-07-26）

切換 selected device 前必須以舊 device identity 完成 stop、clear 與 resource teardown；cleanup 失敗時不能 commit 新 selection 或遺失舊 ownership。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 1 輪：多裝置 contract 最初未定義 active switch 邊界。

## diagnostic-sensitive-detail-no-redaction

**Diagnostic detail 沒有敏感值 redaction**　出現 1 次（2026-07-27 ～ 2026-07-27）

將 exception message 或 process stderr 寫入持久 diagnostic log 時，截長與移除換行不等同 redaction；若 contract 禁止 endpoint、座標或其他敏感值，必須在寫入前產生安全欄位或明確遮蔽，並用含敏感值的 deterministic fixture 驗證。

**出現紀錄**：

- 2026-07-27 — `recover-dropped-device-tunnel` — 提案審查第 1 輪：tunnel stderr 與 backend detail 最初依賴不會移除 endpoint／座標的既有 sanitizer。

## dmg-packaging-contract-test-incomplete

**DMG contract test 未驗證 staging 內容與 replacement boundary**　出現 1 次（2026-07-27 ～ 2026-07-27）

DMG orchestration test 必須檢查 staging 內的 App 與 `/Applications` symlink，並以相鄰 sentinel 證明只替換精確目標；只確認輸出檔存在無法防止內容缺失或過度刪除。

**出現紀錄**：

- 2026-07-27 — `add-package-app-script` — 實作審查第 1 輪：初版 `hdiutil` shim 忽略 `-srcfolder`，也沒有保護相鄰 DMG。

## error-classification-misses-raw-error-string

**錯誤分類關鍵字未涵蓋底層原始錯誤字串**　出現 1 次（2026-08-29 ～ 2026-08-29）

以字串比對分類第三方工具的失敗時，關鍵字必須同時涵蓋底層協定回傳的原始錯誤字串與其被包裝後的例外名稱兩種形式。只比對包裝後的名稱，會在輸出落在只印出原始錯誤字典的路徑時漏判，退回顯示與真正原因無關的階段指引。應回該工具原始碼確認兩種形式的實際字面值。

**出現紀錄**：

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — 提案審查第 1 輪：鎖定判定只涵蓋 `passwordrequired`，但 pymobiledevice3 的 lockdown 回傳的原始字串是 `PasswordProtected`，僅在包裝為 `PasswordRequiredError` 後才出現前者。

## fix-action-claimed-but-not-written

**Fix Action 宣稱已修但檔案未變更**　出現 1 次（2026-08-29 ～ 2026-08-29）

以指令碼批次套用 artifact 編輯時，若把多筆替換累積在記憶體中、最後才一次寫檔，任何一筆中途失敗都會連同已成功的替換一起丟棄，而 round file 的 Fix Actions 卻已記為完成。批次編輯應逐筆讀寫，並在套用後以 grep 驗證舊字串殘留為 0、新字串存在，才寫入 Fix Actions。

**出現紀錄**：

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — 提案審查第 2 輪：Round 1 宣稱改寫的 `tasks.md` task 1.1、1.2 與 1.5 三筆編輯完全未寫入，指令碼在第四筆斷言失敗而中止於寫檔之前。

## generated-user-state-scope-drift

**Tool execution 夾帶個人 user-state binary diff**　出現 1 次（2026-07-27 ～ 2026-07-27）

執行 IDE、generator 或驗收工具後，必須從 change 排除與交付無關的個人 workspace、window 或 UI state binary 變更，避免不可審查的使用者狀態被提交。

**出現紀錄**：

- 2026-07-27 — `add-package-app-script` — 實作審查第 1 輪：Xcode 驗收一度修改 tracked `UserInterfaceState.xcuserstate`。

## helper-contract-deliverables-no-task

**Helper contract deliverables 沒有 task**　出現 1 次（2026-07-26 ～ 2026-07-26）

Implementation Contract 若要求 protocol 文件或 fixtures，tasks 必須明列交付路徑並讓 tests 實際使用，不能只要求 helper implementation。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 1 輪：JSON protocol 文件與 fixtures 最初沒有 backing task。

## host-support-matrix-transport-regression

**新 transport 無條件取代既有支援矩陣**　出現 1 次（2026-09-17 ～ 2026-09-17）

針對新 OS 組合修復 transport 時，若專案仍宣告支援較早 host／device 組合，提案必須定義可驗證的適用政策；不能只以新環境的成功證據把所有既有支援組合無條件切到未驗證 transport。

**出現紀錄**：

- 2026-09-17 — `fix-ios-27-usb-tunnel` — 提案審查第 1 輪：原設計讓 macOS 13+ 全部改走只在 macOS 27實測的 native tunnel，可能使既有支援矩陣退化。

## legacy-runtime-preservation-no-oracle

**版本化 runtime 升級未驗證舊內容保持不變**　出現 1 次（2026-09-17 ～ 2026-09-17）

當 requirement 宣告版本化 runtime 與 legacy sibling共存且不得刪除、覆寫或信任舊內容時，測試必須建立帶 sentinel 的舊目錄，驗證 executable來源為目前版本，並比較舊內容與 metadata保持不變；只斷言新 destination path不足以證偽破壞式升級。

**出現紀錄**：

- 2026-09-17 — `fix-ios-27-usb-tunnel` — 提案審查第 1 輪：task 原本只斷言 versioned destination，無法抓到實作先刪除舊 `current` 再正常啟動新 runtime。

## mode-replacement-failure-state

**Mode replacement 第一個 mutation 失敗時狀態未定義**　出現 1 次（2026-07-26 ～ 2026-07-26）

停止舊 producer 後，新模式第一個外部 mutation 可能失敗；此時不能宣稱 idle 或新模式 active，必須保留 cleanup ownership 與不確定狀態。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 1 輪：point／route replacement 最初只定義成功路徑。

## modified-delta-omits-master-scenario

**MODIFIED delta 漏抄 master 的既有 scenario**　出現 1 次（2026-09-05 ～ 2026-09-05）

以 MODIFIED 承接 master requirement 時，archive 會用 delta 整段取代 master；若手動或以片段截取複製正文而漏掉任一 scenario、Example 或正文段落，該內容會被靜默刪除。撰寫 MODIFIED 時應以程式自 master 擷取整段（至 `@trace` 註解前）再做刻意修改，並以段落 diff 自檢確認差異只剩預期修改、scenario 數量不少於 master。

**出現紀錄**：

- 2026-09-05 — `auto-reconnect-after-usb-replug` — 提案審查第 3 輪：新增 MODIFIED「工作區重置」時以行號區間截取 master，漏掉最後一個 scenario「重置後的鏡頭行為」。

## multi-stream-output-spliced-into-one-message

**多個輸出串流被接合成單一訊息**　出現 1 次（2026-08-29 ～ 2026-08-29）

把 standard error 與 standard output 串接後再做結構切割與接合，會讓兩個獨立串流的內容被拼成一個看似完整的假句子。每個串流應各自摘要；顯示用細節只取單一串流，另一串流僅在前者無可用內容時作為來源。分類若需涵蓋兩個串流，應對各自的摘要分別判定而非接合後判定。

**出現紀錄**：

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — 提案審查第 1 輪：`summarize` 把 stderr 與 stdout 串接後取方框邊界之後的所有行接合，使 stdout 內容被接到例外摘要之後。

## mutation-terminal-state-type-split

**Mutation terminal state 未依操作類型分流**　出現 1 次（2026-07-27 ～ 2026-07-27）

外部mutation共用recovery機制時，terminal state仍須依操作語意分流；active `set` failure可進入position-unknown interruption，但`clear` failure必須保留cleanup ownership與retry，不得被總括failure wording帶回idle或另一個互斥state。

**出現紀錄**：

- 2026-07-27 — `recover-dropped-device-tunnel` — 提案審查第 2、5 輪：clear-specific cleanup contract最初缺少直接測試，後續總括文字仍與`set` failure共用`interrupted(positionUnknown)`。

## numeric-update-cadence-no-test

**數值 update cadence 沒有可控制時間的測試**　出現 1 次（2026-07-26 ～ 2026-07-26）

spec 中「約每秒」之類的數值 acceptance criterion 需要 controllable clock 與 scheduler assertion，僅測距離公式或 timer delay 不能證明 cadence。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 1 輪：一秒 location update cadence 最初沒有直接測試。

## preview-camera-coordinate-dedup

**Preview camera effect 以 coordinate 去重**　出現 1 次（2026-07-30 ～ 2026-07-30）

可被使用者手動操作分隔的 programmatic preview camera intent不能只以coordinate去重；回到相同座標的新使用者要求必須有新的identity，否則舊coordinate會錯誤抑制合法camera effect。

**出現紀錄**：

- 2026-07-30 — `preserve-map-camera-on-click` — 提案審查第 1 輪：原設計保留coordinate-based gate，使「搜尋 A → 點擊 B → 再搜尋 A」的第二次搜尋不會置中。

## preview-camera-intent-stale-clear

**Preview 清除未同步失效 camera intent**　出現 1 次（2026-07-30 ～ 2026-07-30）

當search開始、clear、Reset或其他preview ownership變更清除render state時，相關camera intent也必須在同一owner內同步失效；否則稍後的redraw或precedence變化可能執行已無preview對應的stale effect。

**出現紀錄**：

- 2026-07-30 — `preserve-map-camera-on-click` — 提案審查第 1 輪：原設計漏列`beginSearch(query:)`清除preview時的camera target transition。

## preview-camera-intent-transition-no-test

**Preview camera intent transition 沒有 owner-level test**　出現 1 次（2026-07-30 ～ 2026-07-30）

若camera行為取決於搜尋、直接點擊、clear或failure對intent的分類，測試必須直接執行持有該transition的owner；只向下游canvas注入nil或非nil intent無法防止分類或清理path遺漏。

**出現紀錄**：

- 2026-07-30 — `preserve-map-camera-on-click` — 提案審查第 1 輪：原tasks只測Coordinator注入值，未驗證搜尋成功、地圖點擊、clear、Reset與validation failure的intent轉移。

## privileged-active-lease-stale-retry

**Active privileged lease retry 未驗證 process 存活**　出現 1 次（2026-07-27 ～ 2026-07-27）

同一 idempotency key命中 active lease時，必須先確認底層 privileged process仍存活；不得把已退出 process的舊 `.running` snapshot當成有效 lease回傳。

**出現紀錄**：

- 2026-07-27 — `add-macos-location-simulator` — 實作審查第 2 輪：pending ownership refactor一度讓 active same-key fast path直接回傳 snapshot，未處理 process在 `status`前自行退出。

## privileged-caller-identity-not-audit-token

**Privileged caller trust 未綁定 connection audit token**　出現 1 次（2026-07-27 ～ 2026-07-27）

privileged XPC boundary宣稱驗證connection audit identity時，Security trust decision必須使用connection-bound audit token或等價不可混淆identity；只以PID查`SecCode`，但未把擷取的EUID與audit session納入驗證，不能支撐相同安全宣稱。

**出現紀錄**：

- 2026-07-27 — `add-macos-location-simulator` — 實作審查第 1 輪：helper從connection保存PID／EUID／audit session，但Security驗證只使用PID，與artifacts的audit-token binding宣稱不符。

## privileged-helper-restart-orphan-cleanup

**Privileged helper restart 可能遺留 root child**　出現 1 次（2026-07-27 ～ 2026-07-27）

privileged helper若只在記憶體保存長時間 child process ownership，helper自身crash並由launchd重啟後可能無法辨識或回收舊root child；需要明確的restart ownership與acceptance邊界。

**出現紀錄**：

- 2026-07-27 — `add-macos-location-simulator` — 實作審查第 2 輪：App termination與XPC invalidation已有cleanup，但helper自身termination後的新manager沒有舊child ownership資料。

## privileged-startup-process-untracked

**Privileged process 在啟動完成前沒有可取消 ownership**　出現 1 次（2026-07-27 ～ 2026-07-27）

privileged process launch 與完成 endpoint handshake 之間也必須立即進入可取消、可由 caller invalidation 回收的 ownership；不得持有全域 lock 等待無期限外部輸出，或等成功後才登記 lease。

**出現紀錄**：

- 2026-07-27 — `add-macos-location-simulator` — 實作審查第 1 輪：tunnel process存活但不輸出endpoint時，manager持有lock且尚未登記lease，App crash／XPC invalidation無法保證回收root process。

## programmatic-camera-interaction-misclassification

**Programmatic camera update 誤判為使用者操作**　出現 1 次（2026-07-27 ～ 2026-07-27）

Map camera ownership 必須在執行 programmatic update 時明確標記；只從 delegate callback 或 gesture 狀態推測來源，可能把程式化視角變更誤判為使用者操作，或漏掉真正的 manual interaction。

**出現紀錄**：

- 2026-07-27 — `show-mac-location-on-device-ready` — 實作審查第 1 輪：canvas 最初未在 `setRegion`／`setVisibleMapRect` 期間標記 programmatic ownership。

## reconnect-partial-failure-identity-drift

**Reconnect 中途失敗留下半套 session 與 stale generation**　出現 1 次（2026-09-05 ～ 2026-09-05）

logical reconnect（新 generation、重建 transport、先 clear 再 ready）在中途階段失敗時，adapter 若保留已建立的新 session／lease 而上層仍持舊 generation，之後每筆 mutation 都會落入 `staleGeneration` 而非可重試的 typed 中斷，且再次 reconnect 會平行建立第二個 lease。design 必須為 reconnect 的每個失敗階段定義收斂狀態：不留半套 session、保留 disconnected 記錄、任何時刻最多一個 lease，使下一次使用者動作仍能完整重跑。

**出現紀錄**：

- 2026-09-05 — `auto-reconnect-after-usb-replug` — 提案審查第 1 輪：`reconnect()` 在 clear 階段失敗後 adapter 持有新 generation 的 `cleanupPending` session，SimulationStore 舊 generation 的 stop／start 會收到 `staleGeneration`，重回本 change 要修的「只能重開 App」死局。

## recovery-cancellation-transport-identity-collision

**Recovery cancellation 與 transport identity 共用 generation**　出現 1 次（2026-07-27 ～ 2026-07-27）

取消跨`await` recovery transaction的ownership token必須與current tunnel／DVT pair identity分離；若切換或quit為取消recovery而提前遞增transport generation，仍須送往old transport的clear reply會被錯判為stale。

**出現紀錄**：

- 2026-07-27 — `recover-dropped-device-tunnel` — 提案審查第 2 輪：`DeviceTransportGeneration`一度同時負責transport識別與recovery cancellation，破壞old-device clear。

## recovery-ownership-event-matrix-gap

**Recovery ownership event matrix 缺少直接邊界測試**　出現 1 次（2026-07-27 ～ 2026-07-27）

跨多個`await`的recovery ownership gate若可被disconnect、reconnect、quit或device switch失效，deterministic suspension tests必須直接覆蓋每種ownership event的代表邊界；只測部分事件不能證明其cleanup與stale-replay規則一致。

**出現紀錄**：

- 2026-07-27 — `recover-dropped-device-tunnel` — 提案審查第 3 輪：recovery suspension matrix最初未直接插入device switch並驗證candidate cleanup與old-device clear。

## recursive-isolation-oracle-incomplete

**Isolation test 使用淺層 directory stat 作為 oracle**　出現 1 次（2026-07-27 ～ 2026-07-27）

宣稱隔離 fixture 未修改 repository output 時，必須比較遞迴 content manifest 或受控 sentinel；只比較頂層 directory stat 可能漏掉既有子檔被覆寫。

**出現紀錄**：

- 2026-07-27 — `add-package-app-script` — 實作審查第 1 輪：repository build isolation 初版只比較 `build/` 本身的 mtime、ctime 與 size。

## repository-build-output-not-ignored

**Repository-local build output 未加入 ignore**　出現 1 次（2026-07-27 ～ 2026-07-27）

新增會在 repository 內產生 App、archive、DMG、DerivedData 或其他大型 generated output 的 build 入口時，必須同步加入精確 ignore 規則，避免產物污染工作樹或被誤提交。

**出現紀錄**：

- 2026-07-27 — `add-package-app-script` — 實作審查第 1 輪：新腳本固定寫入 `build/`，但初版沒有在 `.gitignore` 排除該目錄。

## route-terminal-state-transitions

**Route terminal state 缺少後續轉移**　出現 1 次（2026-07-26 ～ 2026-07-26）

狀態仍持有外部資源或模擬效果時，即使名為 completed，也必須定義 stop、interrupt、replacement 與 quit 的後續轉移。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 1 輪：`completed` 仍維持模擬位置，卻未連到 stopping／interrupted。

## spec-delta-internal-requirement-conflict

**同一份 delta 內兩條 requirement 對同一輸入互相牴觸**　出現 1 次（2026-08-29 ～ 2026-08-29）

delta 內 ADDED 與 MODIFIED requirement 若涉及同一輸入或同一類失敗，必須對該輸入的可觀察結果給出一致的規則；一條宣稱使用者看到分類的固定指引、另一條仍以無條件規則要求顯示該階段資訊，會讓 archive 後的 master spec 自相矛盾。替某一類失敗開的例外，必須涵蓋所有同性質的分類。

**出現紀錄**：

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — 提案審查第 1 輪：ADDED requirement 的 Example 宣稱使用者看到例外摘要，但 MODIFIED requirement 與實作都把該輸入分類為裝置鎖定、顯示固定解鎖指引。
- 2026-08-29 — `fix-device-locked-and-favorites-layout` — 提案審查第 4 輪：ADDED requirement 替鎖定與授權兩類都宣告顯示固定指引，MODIFIED requirement 的例外卻只逐字列舉鎖定。

## stale-view-action-cancels-current-request

**Stale view action 取消 current async request**　出現 1 次（2026-07-31 ～ 2026-07-31）

保留 async ownership 的 view action 必須先通過 current model ownership gate，成功後才能取消 view-local async work；重繪前殘留的 stale action 不得先取消較新的 request，再由 model 拒絕。

**出現紀錄**：

- 2026-07-31 — `fix-repeat-search-result-selection` — 提案審查第 1 輪：搜尋結果 action 原規劃沿用 cancel-before-validation 順序，可能讓重繪前的舊列取消較新的 MapKit search 或 reverse-geocode。

## test-marker-keyboard-focus-leak

**Test marker 仍可取得鍵盤 focus**　出現 1 次（2026-07-27 ～ 2026-07-27）

不可見的 AppKit test control 除了零尺寸、透明與禁止 pointer hit testing，還必須明確拒絕 first responder、key-view 與 accessibility focus；隱藏 focus ring 不能證明 control 不會攔截鍵盤操作。

**出現紀錄**：

- 2026-07-27 — `fix-map-sidebar-control-layout` — 提案審查第 1 輪：原設計只要求 marker 零尺寸、透明、`focusRingType = .none` 與 `.allowsHitTesting(false)`，未禁止 `NSButton` 成為 first responder。

## test-marker-production-control-identity-collision

**Test marker 與 production control identity 碰撞**　出現 1 次（2026-07-27 ～ 2026-07-27）

當 DEBUG test marker 與 production control 共用 accessibility identifier 時，測試 collector 必須以不可混淆的型別或結構特徵區分兩者；不得以共享 identifier 排除 marker，否則可能同時漏驗 production control 或讓 marker 斷言取錯節點。

**出現紀錄**：

- 2026-07-27 — `fix-map-sidebar-control-layout` — 提案審查第 1 輪：Reset marker 與 production Reset 共用 `workspace-reset-button`，原 frame oracle 依 identifier 篩選而無法可靠區分。

## test-seam-bypasses-confirmation

**測試 seam 繞過 production 確認邊界**　出現 1 次（2026-07-27 ～ 2026-07-27）

為 hosting 或 automation 測試加入 action seam 時，seam 不得直接呼叫確認後的 mutation 而繞過 production UI 的必要確認；測試應先觸發與可見控制相同的確認入口，驗證確認前狀態不變，再由不可供 production 使用者觸發的測試邊界執行確認。

**出現紀錄**：

- 2026-07-27 — `add-mac-recenter-and-workspace-reset` — 實作審查第 1 輪：Reset hosting marker 曾直接呼叫 `performReset`，繞過 spec 要求的確認對話框，且測試因此未驗證真正的確認順序。

## test-task-requires-missing-seam

**Task 規劃的測試需要不存在的注入 seam**　出現 1 次（2026-08-27 ～ 2026-08-27）

tasks 規劃測試案例時必須確認現有 API surface 可撰寫該測試；若案例需要 private state 的 seed／注入 seam 而 design 未定義該 seam，該案例不可行。應改用 codebase 既有慣例（例如對 generation 型別直接做型別層斷言）或先在 design 明定 seam，不得由 task 隱含引入新機制。

**出現紀錄**：

- 2026-08-27 — `add-favorites` — 提案審查第 1 輪：task 1.2 原要求 model-level 的「generation 耗盡丟出 identityExhausted」案例，但 `mapSearchGeneration` 為 `@Published private(set)` 且無 seed 注入；改為 MapSearchGeneration(rawValue: .max).advanced() 型別層斷言（與 DeviceLocationClientTests 慣例一致）。

## user-visible-device-selection-no-task

**使用者可見的裝置選擇沒有 backing task**　出現 1 次（2026-07-26 ～ 2026-07-26）

adapter discovery tests 不等同使用者可操作的 selection UI；裝置名稱、版本、多裝置選擇與未選定 gating 都需要明確 delivery task。

**出現紀錄**：

- 2026-07-26 — `add-macos-location-simulator` — 提案審查第 1 輪：spec 定義多裝置選擇，但 tasks 最初只覆蓋 adapter discovery。

## view-cancellation-oracle-no-spy

**View cancellation regression 沒有觀察 production path**　出現 1 次（2026-07-31 ～ 2026-07-31）

宣稱 stale view action 不會取消 current async operation 的 regression test，必須以 spy 或等價 seam 直接觀察相同 production cancellation path，並提供成功路徑 positive control 證明 seam 已接線；只驗證 model response 仍可套用，無法排除 view 已錯誤呼叫取消。

**出現紀錄**：

- 2026-07-31 — `fix-repeat-search-result-selection` — 實作審查第 1 輪：兩個 stale-action tests 最初只手動套用 model response，沒有觀察 `cancelSearch()` 與 `cancelPreviewAddressLookup()`，即使 view 先取消較新的 operation 仍會通過。

## view-layout-oracle-incomplete-state-matrix

**View layout oracle 的狀態矩陣不完整**　出現 1 次（2026-07-27 ～ 2026-07-27）

條件式 UI 的 layout regression 必須在每個宣告涵蓋的狀態執行完整 oracle，並要求該狀態應出現的控制；可選的空 expected set、漏掉動態狀態，或只在部分狀態執行 marker／layout 斷言，都會讓測試在布局 contract 失效時仍通過。

**出現紀錄**：

- 2026-07-27 — `fix-map-sidebar-control-layout` — 實作審查第 1 輪 與 3：connected baseline expected set 原為空且未涵蓋 running／paused，補狀態後又漏在 running／paused 重跑 marker oracle。

## view-layout-oracle-misses-status-region

**View layout oracle 漏驗狀態區域**　出現 1 次（2026-07-27 ～ 2026-07-27）

當 spec 要求互動 control 不得覆蓋狀態、錯誤或說明文字時，layout regression oracle 必須同時量測 control 與相關文字區域；只比較 control-vs-control 無法驗證完整的可觀察布局 contract。

**出現紀錄**：

- 2026-07-27 — `fix-map-sidebar-control-layout` — 提案審查第 1 輪：原 frame oracle 只收集 `NSButton`，卻宣稱可驗證按鈕不覆蓋速度、模擬狀態、錯誤與裝置就緒文字。

## view-layout-oracle-partial-visibility

**View layout oracle 只驗證部分可見**　出現 1 次（2026-08-29 ～ 2026-08-29）

當 requirement 要求控制項完整位於可視範圍內時，layout regression oracle 不能只驗證控制項 frame 與 viewport 相交；只剩少量像素可見時也會通過。測試應對 requirement 指定的控制項驗證完整 frame containment，並只保留明確且有限的量測誤差。

**出現紀錄**：

- 2026-08-29 — `fix-device-locked-and-favorites-layout` — 實作審查第 1 輪：側欄測試原本只要求「設定位置」按鈕與 sidebar bounds 相交，無法證偽按鈕被部分推出可視範圍。

## view-lifecycle-request-deduplication

**View lifecycle 無法保存 request 去重 ownership**　出現 1 次（2026-07-27 ～ 2026-07-27）

若 request contract 要求跨視窗或 view 重建對同一 domain identity 至多執行一次，dedup ledger 必須由更長生命週期的 app／store owner 持有，不能放在 view-local model 或 task identity。

**出現紀錄**：

- 2026-07-27 — `show-mac-location-on-device-ready` — 提案審查第 1 輪：per-generation Mac 定位 ledger 最初會因主視窗重開而遺失。

## xcode-test-file-target-membership

**新增 Xcode test file 未納入 target membership**　出現 1 次（2026-07-27 ～ 2026-07-27）

在使用明確 `PBXFileReference`、`PBXBuildFile` 與 Sources build phase 的 Xcode 專案中，新增 test source 的 proposal 與 task 必須同步包含 project registration；只建立檔案不會讓 `xcodebuild test` 編譯或執行該測試。

**出現紀錄**：

- 2026-07-27 — `fix-stale-simulation-controls` — 提案審查第 2 輪：新增 `ContentViewTests.swift` 後，初版 artifacts 未把 `project.pbxproj` target registration 納入 scope。

## xcodegen-regeneration-scope-drift

**XcodeGen regeneration 夾帶非必要 scope drift**　出現 1 次（2026-07-27 ～ 2026-07-27）

只為同步單一 build setting 重新產生 Xcode project 時，必須固定相容 generator 設定並檢查 generated diff；不得把未宣告的 resources、全域 build defaults 或 shared scheme churn 一起納入 change。

**出現紀錄**：

- 2026-07-27 — `add-package-app-script` — 實作審查第 1 輪：XcodeGen 一度把 helper acceptance fixtures、全域 defaults 與 scheme churn 帶入 package-script change。
