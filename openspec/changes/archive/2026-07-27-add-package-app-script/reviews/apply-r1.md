# Cash Apply Review — Round 1

## Reviewer Findings

### Critical

None.

### Warning

1. `severity`: Warning；`confidence`: 99；`layer`: design；`location`: `iPhoneLocationMove/project.yml`、`iPhoneLocationMove.xcodeproj/project.pbxproj`、`iPhoneLocationMove.xcodeproj/xcshareddata/xcschemes/iPhoneLocationMove.xcscheme`；`summary`: 為同步 `MARKETING_VERSION` 執行 XcodeGen 時夾帶 helper `Acceptance/` resources、全域 build defaults、scheme version 與其他非必要 generated deltas，形成 scope drift；`recommendation`: 排除 `Acceptance/`、固定相容的 Xcode version，並將 generated project 正規化為只保留本 change 必要的 `MARKETING_VERSION`；reviewer source：Reviewer A — Adherence、Reviewer B — Quality；`introduced_by`: 本次執行 XcodeGen 後產生的 helper Resources phase、acceptance resource entries 與全域 project/scheme deltas。

2. `severity`: Warning；`confidence`: 98；`layer`: design；`location`: `Scripts/tests/package-app-tests.sh` flags/version cases；`summary`: deterministic tests 只直接證明 `-v` 的成功路徑，未證明 `--version` 與 short alias 行為相同；`recommendation`: 新增 `--version 1.2.3` 成功案例，驗證 build setting、App metadata gate、版本化 DMG 與摘要；reviewer source：Reviewer A — Adherence。

3. `severity`: Warning；`confidence`: 94；`layer`: design；`location`: `Scripts/tests/package-app-tests.sh` embedded requirement case；`summary`: source／embedded mismatch case 沒有建立正確的 source helper plist，因此無法直接防止未來以 source fallback 掩蓋 built metadata 漂移；`recommendation`: fixture 建立正確 source `HelperInfo.plist`，同時讓 embedded metadata shim 回傳錯誤 requirement，並斷言流程失敗；reviewer source：Reviewer A — Adherence。

4. `severity`: Warning；`confidence`: 99；`layer`: design；`location`: `.gitignore`、`Scripts/package-app.sh` build paths；`summary`: 新流程固定在 repository 產生大型 `build/` 與 DerivedData，但 repository 未忽略該目錄；`recommendation`: 將 `/build/` 加入 `.gitignore`；`introduced_by`: 本次新增的 `package-app.sh` 將所有 outputs 與 DerivedData 指向 repository `build/`；reviewer source：Reviewer B — Quality。

5. `severity`: Warning；`confidence`: 98；`layer`: design；`location`: `Scripts/tests/package-app-tests.sh` hdiutil shim／DMG cases；`summary`: DMG shim 未驗證 staging 內的 App、`Applications -> /Applications` symlink，也未保護只替換精確目標 DMG 的 destructive boundary；`recommendation`: 讓 shim 驗證 `-srcfolder` 內容，並以相鄰 DMG sentinel 證明只替換目標；`introduced_by`: 本次新增的 DMG contract tests 未直接覆蓋 spec 指定內容與 replacement boundary；reviewer source：Reviewer B — Quality。

6. `severity`: Warning；`confidence`: 96；`layer`: design；`location`: `Scripts/tests/package-app-tests.sh` `repository_build_state`；`summary`: repository build 不變性只比較頂層 directory stat，覆寫既有子檔可能不改變父目錄 stat而產生假陰性；`recommendation`: 改用遞迴 content manifest／checksum；`introduced_by`: 本次新增的 repository isolation assertion 使用淺層 stat 作為完整目錄 oracle；reviewer source：Reviewer B — Quality。

7. `severity`: Warning；`confidence`: 100；`layer`: text；`location`: `iPhoneLocationMove.xcodeproj/project.xcworkspace/xcuserdata/cash.xcuserdatad/UserInterfaceState.xcuserstate`；`summary`: change 夾帶與打包功能無關的個人 Xcode UI state binary diff；`recommendation`: 還原該檔案；`introduced_by`: 本次 Xcode/XcodeGen 驗收產生的 tracked binary modification；reviewer source：Reviewer B — Quality。

### Suggestion

None.

## Rating

- post-filter cumulative blocking Critical: 0
- post-filter cumulative blocking Warning: 7
- non-blocking triaged finding: 0
- `critical_gap`: false
- `round_type`: full
- 理由：第一輪 7 項 Warning 皆有直接 change evidence 且 `confidence ≥ 80`，全部進入 cumulative blocking set；修正不改變 contract，也不需要 design 未定義的新同步、identity 或 state-machine 機制。

## Fix Actions

- 修改 `.gitignore`：加入 `/build/`，避免 App、DMG、DerivedData 與中間產物進入工作樹候選。
- 修改 `iPhoneLocationMove/project.yml`：固定 `xcodeVersion: "14.3"` 並從 helper sources 排除 `Acceptance`。
- 修改 `iPhoneLocationMove.xcodeproj/project.pbxproj` 並還原 `iPhoneLocationMove.xcodeproj/xcshareddata/xcschemes/iPhoneLocationMove.xcscheme`：重新產生後移除非必要 generated churn，project diff 僅保留兩個 App configurations 的 `MARKETING_VERSION = 1.0`。
- 還原 `iPhoneLocationMove.xcodeproj/project.xcworkspace/xcuserdata/cash.xcuserdatad/UserInterfaceState.xcuserstate`，排除個人 UI state。
- 修改 `Scripts/tests/package-app-tests.sh`：新增 long version success case、正確 source helper plist fixture、embedded mismatch oracle、DMG staging App／symlink validation、精確 DMG replacement sentinel，並以遞迴 SHA-256 manifest 驗證 repository build isolation。
- Post-fix mechanical self-check：`cash validate add-package-app-script`、`bash -n`、`git diff --check`、identifier/version/trust cross-grep 與 10/10 tasks recount 全部通過；project diff 不含 `Acceptance` resources 或 shared scheme 變更。
- Post-fix tests：`Scripts/tests/package-app-tests.sh` 為 117 passed、0 failed；`xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS'` 為 191 tests、0 failures。

## Decision

next_round
