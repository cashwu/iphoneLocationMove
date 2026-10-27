# Cash Apply Review — Round 1

## Reviewer Findings

### Critical

（無）

### Warning

（無）

### Suggestion

- severity: Suggestion｜confidence: 55｜layer: text｜reviewer: B
  - location: `iPhoneLocationMoveTests/TunnelHelperContractTests.swift` `testFoundationLauncherUsesFixedClassicArguments`
  - summary: environment oracle 只斷言 `PYMOBILEDEVICE3_NATIVE_TARGET_UID`／`SUDO_UID` 為 nil，未斷言整份 environment 等於 `processEnvironment`。
  - recommendation: fixture dump 整份 `os.environ` 並比對 `processEnvironment`（允許 Python 注入鍵），或在 harness 預先設定兩個變數以測到「不繼承」。
  - introduced_by: `iPhoneLocationMoveTests/TunnelHelperContractTests.swift` hunk `@@ -677,50 +668,24 @@`（缺口為既有，改寫未補上）。

（Reviewer A Suggestion #1 confidence 40、#2 confidence 35，低於 50 已剔除：`testNativeOnlyTunnelCapabilityIsNotCompatible` 未涵蓋 non-zero exit 分支；environment oracle 同上。）

## Rating

- 累積 blocking set Critical 數：0
- 累積 blocking set Warning 數：0
- non-blocking triaged finding 數：1
- critical_gap: false
- round_type: full
- rationale: 兩位 reviewer 皆確認 Implementation Contract 1–8、tasks 1.1–1.3 與 spec scenarios 已滿足，design 的 code-facing claims 成立，implementation-notes 的 deviation 有正當理由；唯一留存 finding confidence 55 降為 Suggestion，屬 non-blocking；unseeded 第一輪沒有通過 filter 的 Critical／Warning，passed。

## Fix Actions

None; pass condition met.

- non-blocking triage（B Suggestion）：environment oracle 強化屬既有缺口，記為後續可選改進，不在本 change 處理。

## Decision

passed
