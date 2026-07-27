## Context

專案目前以 `iPhoneLocationMove.xcodeproj` 的 shared `iPhoneLocationMove` scheme 建置 App、unit tests 與 `iPhoneLocationMoveTunnelHelper`。README 另外列出 `iPhoneLocationMoveHelper/tests` 的 Python protocol tests。App 與 embedded helper 依同一 Apple Development Team 簽署，`SMPrivilegedExecutables`／`SMAuthorizedClients` 會驗證對方 designated requirement，因此不能沿用參考腳本的 ad-hoc deep re-sign 流程。

本變更只建立本機 developer package；現有 README 已明確排除公證、Developer ID、Mac App Store 與可供他人下載的安裝包。

## Goals / Non-Goals

Goals：

- 提供不依賴 caller current directory 的單一 `Scripts/package-app.sh`。
- 預設執行兩套自動化測試、Release build、簽署與 helper 結構驗證，以及 DMG 包裝。
- 讓 clean、測試、DMG 與版本覆寫可透過少量明確 flags 控制。
- 確保任何必要階段失敗都以非零結束，且不把 pipeline failure 誤報為成功。
- 以不需實際 Xcode build、真實簽章或掛載 DMG 的 deterministic shell tests 驗證 orchestration contract。

Non-Goals：

- 不建立 distribution signing、notarization、stapling 或 release upload。
- 不重新簽署 App 或 helper，不改寫 Xcode project signing settings。
- 不變更 App、helper、Python runtime 或定位功能。
- 不抽象成通用多專案打包框架。

## Decisions

### 1. 使用 repository-relative 固定設定

腳本以 `BASH_SOURCE[0]` 取得 `Scripts/`，再取 parent 作為 `PROJECT_DIR`。固定使用 `iPhoneLocationMove.xcodeproj`、`iPhoneLocationMove` scheme、`build/DerivedData`、`build/Export` 與 `build/iPhoneLocationMove[-<version>].dmg`。在任何 clean 或 build 前，先確認 `iPhoneLocationMove.xcodeproj/project.pbxproj` 與 shared scheme 存在。

此設計避免新增設定檔或環境變數 API；專案只有一個可交付 App target，固定值最容易讀取與除錯。

### 2. 測試是預設 gate

未指定 `--skip-tests` 時，依序執行：

1. `xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -configuration Debug -destination platform=macOS`
2. `python3 -m unittest discover -s iPhoneLocationMoveHelper/tests`

任一命令失敗立即結束，不進入 Release build。`--skip-tests` 同時跳過兩套測試，並在輸出明確標示。腳本不把「scheme 未設定 test action」視為成功，因為此專案已宣告 shared test target。

### 3. Release build 保留 Xcode signing

Release build 使用 `xcodebuild build`，指定 project、scheme、Release configuration、`build/DerivedData` 與 `build/Export`。`iPhoneLocationMove/Info.plist` 的 `CFBundleShortVersionString` 改為引用 `$(MARKETING_VERSION)`，`iPhoneLocationMove/project.yml` 與產生的 `iPhoneLocationMove.xcodeproj/project.pbxproj` 為 App target 提供預設 `MARKETING_VERSION = 1.0`。`--version` 以 `MARKETING_VERSION=<value>` 傳入該次 invocation，且只接受非空、由 ASCII 數字與點組成、每段皆非空的版本字串；腳本不修改 project file。build 後以 `plutil` 驗證 App 的 `CFBundleShortVersionString` 等於指定版本，未指定時則等於 project 預設值。

腳本不呼叫 `codesign --force` 或 `codesign --sign -`。build 後必須找到 `build/Export/iPhoneLocationMove.app` 與 App 內的 `Contents/Library/LaunchServices/com.cash.iPhoneLocationMoveTunnelHelper`，分別執行 strict signature verification。腳本從實際 signed artifacts 讀取 identifier 與 `TeamIdentifier`，要求 App 為 `com.cash.iPhoneLocationMove`、helper 為 `com.cash.iPhoneLocationMoveTunnelHelper`，且兩者 Team 都為 project trust anchor `2LRM76M575`；「兩者相同但不是固定 Team」仍須失敗。腳本以 `otool -X -s __TEXT __info_plist` 從 built embedded helper 擷取實際 plist bytes，以 `xxd -r -p` 還原到腳本建立的 temporary verification file，再用 `plutil` 讀取 metadata；built App 的 `SMPrivilegedExecutables` requirement 與 built helper 的 `SMAuthorizedClients` requirement 必須分別精確對應另一方的 identifier、Apple generic anchor 與固定 Team。缺少產物、metadata 擷取失敗、簽署無效、identifier／Team 漂移或雙向 requirement 不一致都視為打包失敗。temporary verification file 在所有 success／failure paths 都必須由 trap 清除。

### 4. DMG 是預設但可略過的最後階段

未指定 `--no-dmg` 時，腳本在 `build/` 下建立唯一 temporary staging directory，放入 `.app` 與指向 `/Applications` 的 symlink，再以 `hdiutil create -format UDZO` 建立 DMG。以 trap 確保成功或失敗都移除 staging directory。建立前只移除精確解析出的目標 DMG，不碰其他產物。

`--no-dmg` 保留 `.app` 並跳過 `hdiutil`。腳本最後列出 `.app`，有建立 DMG 時再列出 DMG；不自動啟動 App、安裝 helper 或開啟 Finder。

### 5. 以 PATH shims 驗證 orchestration

`Scripts/tests/package-app-tests.sh` 將受測腳本複製到含空白路徑的隔離 temporary project fixture，建立最小 project／scheme／plist markers，並從非 project root current directory 呼叫腳本；temporary PATH 中的 `xcodebuild`、`python3`、`codesign`、`otool`、`xxd`、`plutil` 與 `hdiutil` shims 記錄呼叫及建立假產物。測試覆蓋 `-h`／`--help`、`-v`／`--version`、未知選項、缺少或無效版本、project／shared scheme marker 缺失且 sentinel build content 不被清除、預設流程、所有 flags、App metadata 版本傳遞、測試失敗、build 失敗、helper 缺失、helper metadata 擷取失敗、簽署失敗、相同但錯誤 Team、App／helper identifier mismatch、source／embedded helper requirement mismatch、雙向 requirement mismatch、DMG 失敗與 temporary verification／DMG staging cleanup。測試結束一律清除 fixture。

## Implementation Contract

1. `Scripts/package-app.sh` MUST 使用 macOS 內建 Bash 可執行的語法並啟用 `set -euo pipefail`；所有由腳本解析出的路徑 MUST 正確引用，支援 repository path 含空白。
2. `-h`／`--help` MUST 顯示 flags、預設行為與產物位置並回傳 0；`-v` 與 `--version` MUST 有相同行為；未知選項、`--version` 缺值或版本格式無效 MUST 顯示錯誤並回傳非零，且不得呼叫測試、build 或 packaging commands。
3. 在任何 destructive clean 前，腳本 MUST 驗證 project 與 shared scheme marker。預設只清除 `PROJECT_DIR/build`；`--no-clean` MUST 保留該目錄且不執行 `xcodebuild clean`。tests MUST 以 sentinel build content 證明 marker 缺失時不會先清理，並從非 root current directory、含空白的 fixture path 驗證 path resolution。
4. 除非指定 `--skip-tests`，Release build 前 MUST 依序執行 Xcode tests 與 Python tests；任一失敗 MUST 阻止後續 build。指定 `--skip-tests` 時兩者皆不得執行。
5. Release build MUST 輸出至 `build/Export/iPhoneLocationMove.app`，並讓 `xcodebuild` 的非零狀態原樣造成腳本失敗。`--version X.Y.Z` MUST 傳入 `MARKETING_VERSION=X.Y.Z`，驗證 built App 的 `CFBundleShortVersionString` 等於 `X.Y.Z`，並將 DMG 命名為 `build/iPhoneLocationMove-X.Y.Z.dmg`。未指定版本時 App metadata MUST 保留 project 預設 `1.0`。
6. build 後 MUST 驗證 App、embedded helper、兩者 strict code signature、固定 identifiers、固定 Team `2LRM76M575`，以及 built App 與 built embedded helper 實際 metadata 內的雙向 `SMPrivilegedExecutables`／`SMAuthorizedClients` requirements；MUST NOT 以 repository source plist 代替 built helper metadata oracle，也 MUST NOT 重新簽署任一 binary。任何擷取或驗證失敗 MUST 阻止 DMG 建立。
7. 預設 MUST 建立 `build/iPhoneLocationMove.dmg`；`--no-dmg` MUST 不呼叫 `hdiutil`。DMG staging MUST 在成功與所有 failure paths 清除，且清理範圍只能是腳本建立的 staging path 與精確目標 DMG。
8. 成功時 MUST 回傳 0 並列出實際 `.app` 與可選 DMG 路徑；失敗時 MUST 回傳非零且不得輸出「打包完成」。
9. `Scripts/tests/package-app-tests.sh` MUST 以隔離 fixture 與 command shims 驗證上述 control-flow、short／long arguments、非 root cwd、含空白路徑、marker fail-before-clean、failure propagation、App metadata version、固定 signature identity、built helper metadata extraction、source／embedded mismatch、雙向 requirements 與 cleanup contracts，不得要求真實簽章、實體 iPhone、root 權限或修改 repository 的 `build/`。
10. `README.md` MUST 說明 script prerequisites、預設流程、flags、產物位置與本機 Apple Development package 的限制，且不得將 DMG 描述為已公證或可公開散布。

## Risks / Trade-offs

- Apple Development 簽署需要本機已登入可用 Team；這是現有專案前提。腳本會 fail closed，不提供 ad-hoc fallback。
- `--skip-tests` 可縮短迭代時間但降低信心；它是使用者明確選擇，輸出會標示跳過。
- DMG 只提供方便的本機包裝，不代表通過 Gatekeeper 公證或授權審查；README 會保持此界線。
- PATH shims 驗證 orchestration 而非 Apple tools 本身；實際 Xcode signing correctness 仍由 build 後 strict verification gate 負責。
