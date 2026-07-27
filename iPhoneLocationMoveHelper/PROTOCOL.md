# DVT Helper Protocol

`helper.py` 是長時間執行的 unprivileged process。啟動時以 typed `--rsd-host` 與 `--rsd-port` 連線，並在同一個 process 內持有 `RemoteServiceDiscoveryService`、`DvtProvider` 與 `LocationSimulation` session；它不組合或執行 shell command。

stdin 與 stdout 使用 UTF-8 newline-delimited JSON。每個 request 都必須包含 1–128 字元的 `requestID`，每個 response 都以相同 `requestID` 關聯。額外或缺少欄位會 fail closed。

## Startup events

成功建立 session：

```json
{"event":"ready"}
```

無法建立 session 時回傳 `session-start-failure` 並以非零 status 結束：

```json
{"event":"fatal","error":{"code":"session-start-failure","message":"無法建立 DVT location session","detail":"ErrorType"}}
```

## Requests

設定座標：

```json
{"requestID":"set-1","command":"set","latitude":25.033,"longitude":121.5654}
```

`latitude` 必須介於 `-90...90`，`longitude` 必須介於 `-180...180`，且兩者都必須是有限數字。

清除模擬定位：

```json
{"requestID":"clear-1","command":"clear"}
```

健康檢查：

```json
{"requestID":"ping-1","command":"ping"}
```

正常結束：

```json
{"requestID":"shutdown-1","command":"shutdown"}
```

## Responses

成功：

```json
{"requestID":"set-1","ok":true}
```

失敗：

```json
{"requestID":"set-1","ok":false,"error":{"code":"invalid-coordinate","message":"座標超出合法範圍"}}
```

`error.code` 可能為 `malformed-json`、`invalid-message`、`invalid-request-id`、`unknown-command`、`invalid-coordinate` 或 `backend-failure`。`backend-failure` 會在 `error.detail` 提供例外類型與訊息，並將同一筆結構化事件寫入 stderr。單一 request 失敗不會讓 helper crash；caller 可使用新的 `requestID` 重試。只有 `shutdown` acknowledgement、stdin EOF 或 fatal session error 會結束 process。
