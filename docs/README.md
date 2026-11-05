# iPhone Location Move 文件

- [`specs/`](specs/) — 目前生效的行為規格（以 SHALL／MUST 與 Scenario 描述），共 6 個 capability：
  - [`location-simulation`](specs/location-simulation.md) — 定位模擬主體：搜尋選點、單點、A/B 步行路線、暫停／調速、停止與 clear、工作區重置
  - [`ios-device-session`](specs/ios-device-session.md) — 裝置 session：支援環境、USB 偵測、privileged tunnel 邊界、重連與結束清理
  - [`device-tunnel-recovery`](specs/device-tunnel-recovery.md) — transport 中斷的辨識與單次 recovery
  - [`mac-map-initial-location`](specs/mac-map-initial-location.md) — 裝置就緒後顯示 Mac 位置
  - [`favorite-places`](specs/favorite-places.md) — 我的最愛
  - [`macos-build-packaging`](specs/macos-build-packaging.md) — `Scripts/package-app.sh` 本機打包
- [`changes.md`](changes.md) — 15 個已完成 change 的歷史與 tasks 清單
- [`designs/`](designs/) — 15 個 change 各自的設計文件（Context、Decisions、Risks、Implementation Contract），檔名為 `<日期>-<change 名稱>.md`
- [`implementation-notes.md`](implementation-notes.md) — 實作過程記錄的偏離、阻塞與環境限制
- [`signals.md`](signals.md) — 73 條 review 經驗教訓：反覆出現的問題型態與規則，可當新設計／review 的 checklist
