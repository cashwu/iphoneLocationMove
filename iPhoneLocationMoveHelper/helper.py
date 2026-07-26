from __future__ import annotations

import argparse
import asyncio
import json
import math
import sys
from contextlib import AsyncExitStack
from typing import Any, Protocol, TextIO


class LocationBackend(Protocol):
    async def set_location(self, latitude: float, longitude: float) -> None: ...

    async def clear_location(self) -> None: ...


class ProtocolProcessor:
    _COMMAND_FIELDS = {
        "set": {"requestID", "command", "latitude", "longitude"},
        "clear": {"requestID", "command"},
        "ping": {"requestID", "command"},
        "shutdown": {"requestID", "command"},
    }

    def __init__(self, backend: LocationBackend) -> None:
        self._backend = backend

    async def handle_line(self, line: str) -> tuple[dict[str, Any], bool]:
        try:
            message = json.loads(line)
        except (json.JSONDecodeError, UnicodeDecodeError):
            return self._error(None, "malformed-json", "訊息不是有效的 JSON"), False

        if not isinstance(message, dict):
            return self._error(None, "invalid-message", "訊息必須是 JSON object"), False

        request_id = message.get("requestID")
        if not isinstance(request_id, str) or not request_id or len(request_id) > 128:
            return self._error(None, "invalid-request-id", "requestID 必須是 1–128 字元字串"), False

        command = message.get("command")
        if command not in self._COMMAND_FIELDS:
            return self._error(request_id, "unknown-command", "不支援的 command"), False

        if set(message) != self._COMMAND_FIELDS[command]:
            return self._error(request_id, "invalid-message", "訊息欄位不符合 command contract"), False

        try:
            if command == "set":
                latitude = self._coordinate(message["latitude"], -90, 90)
                longitude = self._coordinate(message["longitude"], -180, 180)
                await self._backend.set_location(latitude, longitude)
            elif command == "clear":
                await self._backend.clear_location()
        except ValueError:
            return self._error(request_id, "invalid-coordinate", "座標超出合法範圍"), False
        except Exception as error:
            return self._error(
                request_id,
                "backend-failure",
                "DVT location request 失敗",
                type(error).__name__,
            ), False

        return {"requestID": request_id, "ok": True}, command == "shutdown"

    @staticmethod
    def _coordinate(value: Any, minimum: float, maximum: float) -> float:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError("coordinate must be numeric")
        coordinate = float(value)
        if not math.isfinite(coordinate) or not minimum <= coordinate <= maximum:
            raise ValueError("coordinate outside range")
        return coordinate

    @staticmethod
    def _error(
        request_id: str | None,
        code: str,
        message: str,
        detail: str | None = None,
    ) -> dict[str, Any]:
        error: dict[str, str] = {"code": code, "message": message}
        if detail is not None:
            error["detail"] = detail
        return {"requestID": request_id, "ok": False, "error": error}


class PymobiledeviceBackend:
    def __init__(self, host: str, port: int) -> None:
        self._host = host
        self._port = port
        self._stack: AsyncExitStack | None = None
        self._location: Any = None

    async def __aenter__(self) -> PymobiledeviceBackend:
        from pymobiledevice3.remote.remote_service_discovery import (
            RemoteServiceDiscoveryService,
        )
        from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
        from pymobiledevice3.services.dvt.instruments.location_simulation import (
            LocationSimulation,
        )

        stack = AsyncExitStack()
        try:
            rsd = await stack.enter_async_context(
                RemoteServiceDiscoveryService((self._host, self._port))
            )
            dvt = await stack.enter_async_context(DvtProvider(rsd))
            self._location = await stack.enter_async_context(LocationSimulation(dvt))
        except BaseException:
            await stack.aclose()
            raise
        self._stack = stack
        return self

    async def __aexit__(self, *_: Any) -> None:
        if self._stack is not None:
            await self._stack.aclose()
        self._location = None
        self._stack = None

    async def set_location(self, latitude: float, longitude: float) -> None:
        if self._location is None:
            raise RuntimeError("DVT session is not ready")
        await self._location.set(latitude, longitude)

    async def clear_location(self) -> None:
        if self._location is None:
            raise RuntimeError("DVT session is not ready")
        await self._location.clear()


async def serve(
    backend: LocationBackend,
    input_stream: TextIO = sys.stdin,
    output_stream: TextIO = sys.stdout,
) -> None:
    processor = ProtocolProcessor(backend)
    output_stream.write('{"event":"ready"}\n')
    output_stream.flush()

    while True:
        line = await asyncio.to_thread(input_stream.readline)
        if line == "":
            return
        response, should_shutdown = await processor.handle_line(line)
        output_stream.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n")
        output_stream.flush()
        if should_shutdown:
            return


def parse_arguments(arguments: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Long-lived pymobiledevice3 DVT location helper")
    parser.add_argument("--rsd-host", required=True)
    parser.add_argument("--rsd-port", required=True, type=int)
    parsed = parser.parse_args(arguments)
    if not parsed.rsd_host.strip():
        parser.error("--rsd-host must not be empty")
    if not 1 <= parsed.rsd_port <= 65535:
        parser.error("--rsd-port must be between 1 and 65535")
    return parsed


async def async_main(arguments: list[str]) -> int:
    options = parse_arguments(arguments)
    try:
        async with PymobiledeviceBackend(options.rsd_host, options.rsd_port) as backend:
            await serve(backend)
    except Exception as error:
        event = {
            "event": "fatal",
            "error": {
                "code": "session-start-failure",
                "message": "無法建立 DVT location session",
                "detail": type(error).__name__,
            },
        }
        sys.stdout.write(json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(async_main(sys.argv[1:])))
