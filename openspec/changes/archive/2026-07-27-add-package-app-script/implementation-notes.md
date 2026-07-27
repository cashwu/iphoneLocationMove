<!-- cash-apply implementation notes | change: add-package-app-script | initialized: 2026-07-27 20:26 | no entries below means no deviations or open questions were recorded -->

## 2026-07-27 20:36 — Universal helper metadata 改由單一 architecture slice 擷取

- 類別：deviation
- 任務：3.3
- 內容：原設計直接對 universal embedded helper 執行 `otool -X -s __TEXT __info_plist | xxd -r -p`，會把 architecture address 欄位與 little-endian 32-bit word 順序一起解碼而產生無效 plist。改為先以 `lipo -thin "$(uname -m)"` 擷取目前 host architecture slice，再以 `awk` 移除 address、將每個 word 正規化為 byte order，最後交由既有 `xxd` 流程解碼。
- 原因：此替代手段仍以 built embedded helper 作為 oracle，且不改變可觀察行為、interface／資料形狀、失敗模式或驗收標準；不需要 `a synchronization primitive, identity/generation type, or state machine not defined in design.md`。
