# macos-build-packaging Specification

## Purpose

macos-build-packaging capability.

## Requirements

### Requirement: 單一可重複的 macOS 打包入口

系統 SHALL 提供 `Scripts/package-app.sh`，從 repository 中任意 current directory 呼叫時皆以腳本自身位置解析專案，並以固定 project、shared scheme 與輸出目錄執行打包。系統 MUST 在任何 clean 或 build 前驗證 project 與 shared scheme 存在。

#### Scenario: 從非專案根目錄執行

- **GIVEN** 使用者的 current directory 不是 repository root
- **WHEN** 使用者以絕對或相對路徑執行 `Scripts/package-app.sh`
- **THEN** 腳本以自身位置找到 `iPhoneLocationMove.xcodeproj`
- **AND** 產物寫入 repository root 的 `build/`

#### Scenario: 專案 marker 缺失

- **GIVEN** project file 或 shared scheme marker 不存在
- **WHEN** 使用者執行打包腳本
- **THEN** 腳本 MUST 回傳非零並指出缺失項目
- **AND** 腳本 MUST NOT 清除輸出或呼叫測試、build 與 DMG 工具

<!-- @trace
source: add-package-app-script
updated: 2026-07-27
code:
  - Scripts/package-app.sh
  - Scripts/tests/package-app-tests.sh
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/Info.plist
  - iPhoneLocationMove/project.yml
tests:
-->

### Requirement: 明確且安全的命令列介面

腳本 SHALL 支援 `-h`／`--help`、`-v`／`--version`、`--no-clean`、`--skip-tests` 與 `--no-dmg`。版本值 MUST 為以點分隔的非空 ASCII 數字段。未知選項與無效參數 MUST fail closed，且不得開始 build pipeline。

#### Scenario: 顯示說明

- **WHEN** 使用者傳入 `--help`
- **THEN** 腳本顯示所有 flags、預設行為及 `.app`／DMG 產物位置
- **AND** 回傳 0 且不呼叫任何 build pipeline command

#### Scenario: 版本參數無效

- **WHEN** 使用者傳入缺值、空段或非數字的 `--version`
- **THEN** 腳本回傳非零並顯示版本格式錯誤
- **AND** 不呼叫測試、build 或 DMG 工具

#### Scenario: 短參數 aliases

- **WHEN** 使用者分別傳入 `-h` 或 `-v 1.2.3`
- **THEN** 腳本 MUST 與 `--help` 或 `--version 1.2.3` 產生相同行為

#### Scenario: 未知選項

- **WHEN** 使用者傳入未支援的選項
- **THEN** 腳本回傳非零並顯示未知選項與 help
- **AND** 不呼叫測試、build 或 DMG 工具

<!-- @trace
source: add-package-app-script
updated: 2026-07-27
code:
  - Scripts/package-app.sh
  - Scripts/tests/package-app-tests.sh
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/Info.plist
  - iPhoneLocationMove/project.yml
tests:
-->

### Requirement: 測試優先的 Release build

腳本 SHALL 預設在 Release build 前依序執行 `iPhoneLocationMove` shared scheme 的 macOS tests 與 `iPhoneLocationMoveHelper/tests` Python tests。任一測試或 build command 失敗 MUST 立即停止後續階段並保留非零結果。使用者 MAY 以 `--skip-tests` 明確跳過兩套測試。

#### Scenario: 預設測試與建置成功

- **WHEN** 使用者不帶跳過 flags 執行腳本
- **THEN** 腳本依序執行 Xcode tests、Python tests 與 Release build
- **AND** Release App 位於 `build/Export/iPhoneLocationMove.app`

#### Scenario: 任一測試失敗

- **GIVEN** Xcode tests 或 Python tests 回傳非零
- **WHEN** 腳本執行預設流程
- **THEN** 腳本回傳非零
- **AND** MUST NOT 執行 Release build、簽署驗證或 DMG 建立

#### Scenario: 明確跳過測試

- **WHEN** 使用者傳入 `--skip-tests`
- **THEN** 腳本清楚標示兩套測試已跳過
- **AND** 不呼叫 Xcode test 或 Python unittest
- **AND** 繼續執行 Release build

#### Scenario: 保留既有 build 目錄

- **WHEN** 使用者傳入 `--no-clean`
- **THEN** 腳本 MUST NOT 移除 `build/` 或執行 `xcodebuild clean`
- **AND** 使用既有 derived data 執行其餘所選階段

<!-- @trace
source: add-package-app-script
updated: 2026-07-27
code:
  - Scripts/package-app.sh
  - Scripts/tests/package-app-tests.sh
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/Info.plist
  - iPhoneLocationMove/project.yml
tests:
-->

### Requirement: 保留 privileged helper 的簽署信任

腳本 MUST 使用 Xcode 既有 Apple Development signing 建置 App 與 embedded `iPhoneLocationMoveTunnelHelper`，MUST NOT ad-hoc 或 deep re-sign 任一產物。DMG 建立前，腳本 SHALL 驗證 App 與 helper 都存在、strict code signature 有效、identifier 分別為 `com.cash.iPhoneLocationMove` 與 `com.cash.iPhoneLocationMoveTunnelHelper`、兩者 `TeamIdentifier` 都為 `2LRM76M575`，且 built App Info.plist 的 `SMPrivilegedExecutables` 與 built embedded helper `__TEXT,__info_plist` 的 `SMAuthorizedClients` requirements 都精確授權另一方的固定 identifier、Apple generic anchor 與 Team。系統 MUST NOT 以 repository source helper plist 代替 built helper metadata oracle。

#### Scenario: App 與 helper 簽署一致

- **GIVEN** Release build 產生 App 與 embedded helper
- **AND** 兩者 strict code signature 有效、identifier 與固定 Team 正確
- **WHEN** 腳本執行產物驗證
- **THEN** 雙向 `SMJobBless` requirements 與實際 signed identities 一致
- **AND** 驗證通過並繼續可選 DMG 階段

#### Scenario: helper 缺失或 trust contract 無效

- **GIVEN** embedded helper 不存在、任一簽署無效、identifier 漂移、Team 不是 `2LRM76M575` 或雙向 requirement 不一致
- **WHEN** 腳本執行產物驗證
- **THEN** 腳本回傳非零並指出驗證失敗
- **AND** MUST NOT 建立 DMG 或宣告打包完成

#### Scenario: 兩個產物同屬錯誤 Team

- **GIVEN** App 與 helper 的 `TeamIdentifier` 相同但不是 `2LRM76M575`
- **WHEN** 腳本執行產物驗證
- **THEN** 腳本 MUST 回傳非零
- **AND** MUST NOT 把「兩者相同」視為通過 privileged helper trust gate

#### Scenario: embedded helper metadata 與 source 漂移

- **GIVEN** repository source helper plist 宣告正確 requirement
- **AND** built embedded helper 的 `__TEXT,__info_plist` 攜帶不同或無法解析的 `SMAuthorizedClients`
- **WHEN** 腳本執行產物驗證
- **THEN** 腳本 MUST 回傳非零
- **AND** MUST NOT 以 source plist 的正確值掩蓋實際出貨 metadata 漂移

<!-- @trace
source: add-package-app-script
updated: 2026-07-27
code:
  - Scripts/package-app.sh
  - Scripts/tests/package-app-tests.sh
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/Info.plist
  - iPhoneLocationMove/project.yml
tests:
-->

### Requirement: 可選且可清理的 DMG 包裝

腳本 SHALL 預設建立包含 `iPhoneLocationMove.app` 與 `/Applications` symlink 的 UDZO DMG。`--version X.Y.Z` SHALL 只覆寫該次 build 的 `MARKETING_VERSION` 並產生 `build/iPhoneLocationMove-X.Y.Z.dmg`；未指定版本時產生 `build/iPhoneLocationMove.dmg`。使用者 MAY 以 `--no-dmg` 保留驗證後的 `.app` 而不呼叫 DMG 工具。

#### Scenario: 建立版本化 DMG

- **WHEN** 使用者傳入 `--version 1.2.3`
- **THEN** Release build 收到 `MARKETING_VERSION=1.2.3`
- **AND** built App 的 `CFBundleShortVersionString` 為 `1.2.3`
- **AND** 腳本建立 `build/iPhoneLocationMove-1.2.3.dmg`
- **AND** project file 不因版本覆寫而修改

#### Scenario: 跳過 DMG

- **WHEN** 使用者傳入 `--no-dmg`
- **THEN** 腳本不呼叫 `hdiutil`
- **AND** 成功摘要只列出驗證後的 `.app`

#### Scenario: DMG 建立失敗

- **GIVEN** `hdiutil create` 回傳非零
- **WHEN** 腳本執行 DMG 階段
- **THEN** 腳本回傳非零且不宣告打包完成
- **AND** 腳本建立的 staging directory MUST 被移除

<!-- @trace
source: add-package-app-script
updated: 2026-07-27
code:
  - Scripts/package-app.sh
  - Scripts/tests/package-app-tests.sh
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/Info.plist
  - iPhoneLocationMove/project.yml
tests:
-->

### Requirement: 打包流程具備 deterministic orchestration tests

系統 SHALL 提供不依賴真實 Xcode build、簽章、實體 iPhone 或 root 權限的 shell tests，驗證命令列介面、short／long aliases、從非 root current directory 與含空白路徑執行、marker fail-before-clean、命令順序、flag 行為、failure propagation、App metadata version、固定簽署 identity、built helper metadata extraction、source／embedded mismatch、雙向 requirements，以及 temporary verification／DMG staging cleanup。測試 MUST 在隔離 fixture 執行且 MUST NOT 修改 repository 的 `build/`。

#### Scenario: 以 command shims 驗證成功與失敗路徑

- **WHEN** 執行 `Scripts/tests/package-app-tests.sh`
- **THEN** 測試以隔離 temporary project 與 PATH shims 驗證正常流程及每個指定 failure boundary
- **AND** 測試完成後移除 fixture
- **AND** repository 的 `build/` 不因測試而建立、清除或修改

<!-- @trace
source: add-package-app-script
updated: 2026-07-27
code:
  - Scripts/package-app.sh
  - Scripts/tests/package-app-tests.sh
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/Info.plist
  - iPhoneLocationMove/project.yml
tests:
-->

### Requirement: 文件維持本機 package 邊界

README SHALL 說明腳本 prerequisites、預設流程、flags、產物位置與 Apple Development signing 限制，MUST NOT 將產出的 App 或 DMG 描述為已公證、適合公開散布或可繞過既有授權與安全審查。

#### Scenario: 開發者查閱打包說明

- **WHEN** 開發者閱讀 README 的打包章節
- **THEN** 可辨識預設命令、快速 build flags 與輸出位置
- **AND** 可辨識產物僅供已設定 Team 的本機開發與驗證
- **AND** 公開散布仍需 Developer ID、公證、授權與 privileged helper security review

<!-- @trace
source: add-package-app-script
updated: 2026-07-27
code:
  - Scripts/package-app.sh
  - Scripts/tests/package-app-tests.sh
  - iPhoneLocationMove.xcodeproj/project.pbxproj
  - iPhoneLocationMove/Info.plist
  - iPhoneLocationMove/project.yml
tests:
-->
