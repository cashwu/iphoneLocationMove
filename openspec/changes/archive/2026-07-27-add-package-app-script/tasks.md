## 1. TDD：建立打包腳本 contract tests

- [x] 1.1 在 `Scripts/tests/package-app-tests.sh` 建立含空白路徑的隔離 temporary project fixture 與 `xcodebuild`、`python3`、`codesign`、`otool`、`xxd`、`plutil`、`hdiutil` PATH shims；從非 project root current directory 呼叫受測腳本，以 failing tests 覆蓋 `-h`／`--help`、`-v`／`--version`、未知選項、缺少／無效版本，以及 project／shared scheme marker 缺失，並用 sentinel build content 與空 command log 確認無效輸入或 marker 缺失不會清理或啟動 pipeline。
- [x] 1.2 在 `Scripts/tests/package-app-tests.sh` 加入預設流程與 flags 的 failing tests：驗證 clean、Xcode test、Python test、Release build、版本傳遞、`--no-clean`、`--skip-tests`、`--no-dmg`、固定輸出路徑及命令順序。
- [x] 1.3 在 `Scripts/tests/package-app-tests.sh` 加入 failure-boundary tests：Xcode／Python test failure、Release build failure、App 或 helper 缺失、built helper metadata 擷取失敗、strict signature failure、相同但錯誤的 Team、App／helper identifier mismatch、source／embedded helper requirement mismatch、`SMPrivilegedExecutables`／`SMAuthorizedClients` requirement mismatch、DMG failure 與所有路徑的 temporary verification／DMG staging cleanup；驗證 fixture 不建立、清除或修改 repository 的 `build/`。

## 2. 實作 build 與 packaging pipeline

- [x] 2.1 在 `Scripts/package-app.sh` 建立 macOS Bash 3.2 相容的腳本骨架，啟用 `set -euo pipefail`，以 `BASH_SOURCE[0]` 解析並引用 project paths，在 clean 前驗證 project 與 shared scheme，實作 help、argument parsing 與嚴格版本格式驗證，使 1.1 tests 通過。
- [x] 2.2 將 `iPhoneLocationMove/Info.plist` 的 `CFBundleShortVersionString` 接到 `$(MARKETING_VERSION)`，在 `iPhoneLocationMove/project.yml` 設定 App target 預設 `MARKETING_VERSION: 1.0` 並以 XcodeGen 同步 `iPhoneLocationMove.xcodeproj/project.pbxproj`；在 `Scripts/package-app.sh` 實作精確 `build/` clean、可選 `xcodebuild clean`、預設 Xcode／Python tests、Release build、`MARKETING_VERSION` 覆寫、`.app` 存在與 built App metadata 驗證，保留 command failure 狀態，使 1.2 tests 通過。
- [x] 2.3 在 `Scripts/package-app.sh` 以 `otool`／`xxd` 從 built embedded `iPhoneLocationMoveTunnelHelper` 擷取 `__TEXT,__info_plist`，再驗證 App／helper strict code signature、固定 identifiers、固定 Team `2LRM76M575` 與兩個 built artifacts metadata 內的雙向 `SMPrivilegedExecutables`／`SMAuthorizedClients` requirements，且不得以 source plist 代替 oracle 或重新簽署產物；實作 UDZO DMG staging、Applications symlink、精確目標 replacement、trap cleanup、`--no-dmg` 與成功摘要，使 1.3 tests 通過。
- [x] 2.4 將 `Scripts/package-app.sh` 與 `Scripts/tests/package-app-tests.sh` 設為 executable，執行 `Scripts/tests/package-app-tests.sh` 並修正所有 orchestration regressions。

## 3. 文件與實際工具鏈驗證

- [x] [P] 3.1 更新 `README.md`，記錄 `Scripts/package-app.sh` prerequisites、預設流程、flags、`build/Export/iPhoneLocationMove.app` 與 DMG 路徑，以及 Apple Development package 未公證、不可視為公開發佈產物的限制。
- [x] 3.2 執行不需 root 或實體 iPhone 的現有測試：`xcodebuild test -project iPhoneLocationMove.xcodeproj -scheme iPhoneLocationMove -destination 'platform=macOS'` 與 `python3 -m unittest discover -s iPhoneLocationMoveHelper/tests`。
- [x] 3.3 在已設定 Team 的本機執行 `Scripts/package-app.sh --no-dmg`，確認 Release `.app` 與 embedded helper 存在、helper `__TEXT,__info_plist` 可擷取、strict signature、固定 identifiers、Team `2LRM76M575` 與兩個 built artifacts metadata 內的雙向 `SMJobBless` requirements 全部有效；再執行預設 DMG 流程，確認 `.app`、Applications symlink、`--version` 對應的 App metadata 與版本化 DMG 輸出。若本機 signing prerequisite 不成立，記錄明確失敗結果，MUST NOT 以 source plist 或 ad-hoc signing 繞過 gate。
