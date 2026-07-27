<!-- cash-apply implementation notes | change: add-macos-location-simulator | initialized: 2026-07-26 20:36 | no entries below means no deviations or open questions were recorded -->

## 2026-07-26 21:17 — privileged runtime 改用離線 target 安裝
- 類別：deviation
- 任務：2.4
- 內容：原設計預期以 root-owned Python 建立不含 symlink 的 managed runtime；實際的 `/usr/bin/python3 -m venv --copies` 回報 `This build of python cannot create venvs without using symlinks`。實作改為由同一個 root-owned、不可由一般使用者修改且版本 `>=3.9` 的 `/usr/bin/python3`，將 helper trust anchor 驗證過的 wheelhouse 以固定 `pip install --isolated --no-index --target` 安裝到 root-owned staging，並產生固定 Python entrypoint 後 atomic publish。
- 原因：替代手段維持 typed XPC contract、offline pinned payload、root ownership、無 symlink、無 network `pip`、digest 驗證、atomic publish 與結構化失敗語意，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`；因此依 blocker triage 的機制替換分支記錄後繼續。

## 2026-07-26 22:24 — dev-signed build 改用 SMJobBless 安裝 helper
- 類別：deviation
- 任務：7.3
- 內容：原設計使用 `SMAppService.daemon(plistName:)` 註冊 bundled LaunchDaemon；本機 macOS 26.5 SDK 明定含 LaunchDaemon 的 App 必須 notarized，實測 Apple Development 簽署的 App 無論位於 `/tmp` 或 `/Applications`，`SMAppService.status` 都回傳 `.notFound`。依使用者確認的 dev-certificate-only 發佈邊界，改以仍支援 macOS 13+ 的 `SMJobBless` 完成管理員核准、helper 安裝與 launchd 註冊。
- 原因：替代手段只更換 privileged helper 的安裝／註冊機制，維持既有 typed XPC contract、caller code signature／Team ID 驗證、`TunnelLeaseID` ownership、root-owned offline runtime integrity、結構化失敗與 uninstall／cleanup 驗收標準，也不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`；因此依 blocker triage 的機制替換分支記錄後繼續。
