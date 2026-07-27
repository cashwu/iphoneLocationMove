## Summary

新增一支可從 repository 任意工作目錄呼叫的 macOS 打包腳本，統一執行測試、清理、Release 建置、簽署驗證與 DMG 包裝，讓本機可重複產出 `iPhoneLocationMove.app` 與安裝映像。

## Motivation

目前 README 只提供分散的 Xcode 與 Python 測試指令，沒有單一、可重複的 Release build 入口。手動選擇 scheme、輸出路徑與打包步驟容易漏跑測試、產物位置不一致，亦可能不慎以 ad-hoc 簽署破壞 App 與 `SMJobBless` helper 的同 Team trust contract。需要一個貼近 `/Users/cash/Github/Tubify/Scripts/package-app.sh` 操作方式、但符合本專案 privileged helper 簽署限制的最小腳本。

## Proposed Solution

在 `Scripts/package-app.sh` 提供單一打包入口。腳本以自身位置解析 project root，驗證 Xcode project 與 shared scheme，預設清理輸出、執行 macOS Xcode tests 與 Python protocol tests，再以 Release configuration 建置至固定的 `build/Export`。建置完成後驗證 `.app`、內嵌 privileged helper、固定 identifier／Team、雙向 `SMJobBless` requirement 與 code signature，並預設建立包含 Applications symlink 的壓縮 DMG。

腳本支援 `-h`／`--help`、`-v`／`--version`、`--no-clean`、`--skip-tests` 與 `--no-dmg`；未知選項、缺少版本值、測試失敗、build pipeline 失敗、產物缺失或簽署驗證失敗均回傳非零。版本覆寫只作用於該次 `xcodebuild`，且建置後的 App metadata 與 DMG 檔名必須反映該版本，不得修改 project file。終端輸出明確列出各階段與最終產物路徑。

## Non-Goals

- 不加入 Developer ID、hardened runtime、公證、Mac App Store 或正式公開發佈流程。
- 不改變既有 Apple Development Team、entitlements、helper authorization requirement 或 runtime trust anchor。
- 不安裝 Xcode、Python、XcodeGen 或其他依賴。
- 不修改 App、helper 或定位模擬的執行期行為。
- 不自動開啟 Finder，也不自動安裝或啟動建置產物。

## Alternatives Considered

- 直接複製 Tubify 腳本並改 project name：會套用 ad-hoc deep signing，破壞本專案 App 與 privileged helper 的簽署信任關係，因此不採用。
- 只在 README 增加手動指令：無法保證測試、輸出路徑、錯誤傳播與簽署檢查一致。
- 導入 Fastlane 或其他打包框架：對單一 Xcode project 與本機 DMG 需求過重，增加非必要依賴。

## Capabilities

### New Capabilities

- `macos-build-packaging`：以單一 shell 入口重複執行測試、Release build、簽署驗證與可選 DMG 包裝。

### Modified Capabilities

- (none)

## Impact

- Affected specs:
  - New: `openspec/changes/add-package-app-script/specs/macos-build-packaging/spec.md`
- Affected code:
  - New:
    - `Scripts/package-app.sh`
    - `Scripts/tests/package-app-tests.sh`
  - Modified:
    - `README.md`
    - `iPhoneLocationMove/Info.plist`
    - `iPhoneLocationMove/project.yml`
    - `iPhoneLocationMove.xcodeproj/project.pbxproj`
  - Removed:
    - (none)
