import asyncio
import json
import sys
import unittest
from pathlib import Path

HELPER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HELPER_ROOT))

from helper import ProtocolProcessor


class FakeLocationBackend:
    def __init__(self) -> None:
        self.set_calls: list[tuple[float, float]] = []
        self.clear_calls = 0
        self.fail_next: Exception | None = None

    async def set_location(self, latitude: float, longitude: float) -> None:
        if self.fail_next is not None:
            error = self.fail_next
            self.fail_next = None
            raise error
        self.set_calls.append((latitude, longitude))

    async def clear_location(self) -> None:
        if self.fail_next is not None:
            error = self.fail_next
            self.fail_next = None
            raise error
        self.clear_calls += 1


class ProtocolProcessorTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.backend = FakeLocationBackend()
        self.processor = ProtocolProcessor(self.backend)
        self.fixtures = HELPER_ROOT / "tests" / "fixtures"

    async def test_set_validates_and_correlates_request_id(self) -> None:
        response, should_shutdown = await self.processor.handle_line(
            (self.fixtures / "valid_set.json").read_text()
        )

        self.assertEqual(response, {"requestID": "set-1", "ok": True})
        self.assertFalse(should_shutdown)
        self.assertEqual(self.backend.set_calls, [(25.033, 121.5654)])

    async def test_invalid_coordinate_is_rejected_without_backend_call(self) -> None:
        response, should_shutdown = await self.processor.handle_line(
            (self.fixtures / "invalid_coordinate.json").read_text()
        )

        self.assertEqual(response["requestID"], "set-invalid")
        self.assertEqual(response["error"]["code"], "invalid-coordinate")
        self.assertFalse(should_shutdown)
        self.assertEqual(self.backend.set_calls, [])

    async def test_malformed_json_returns_structured_error_and_keeps_running(self) -> None:
        response, should_shutdown = await self.processor.handle_line(
            (self.fixtures / "malformed.json").read_text()
        )

        self.assertIsNone(response["requestID"])
        self.assertEqual(response["error"]["code"], "malformed-json")
        self.assertFalse(should_shutdown)

    async def test_unknown_command_is_rejected(self) -> None:
        response, should_shutdown = await self.processor.handle_line(
            (self.fixtures / "unknown_command.json").read_text()
        )

        self.assertEqual(response["requestID"], "unknown-1")
        self.assertEqual(response["error"]["code"], "unknown-command")
        self.assertFalse(should_shutdown)

    async def test_clear_failure_is_visible_and_retryable(self) -> None:
        self.backend.fail_next = TimeoutError("DVT request timed out")

        failed, _ = await self.processor.handle_line('{"requestID":"clear-1","command":"clear"}')
        succeeded, _ = await self.processor.handle_line('{"requestID":"clear-2","command":"clear"}')

        self.assertEqual(failed["error"]["code"], "backend-failure")
        self.assertEqual(
            failed["error"]["detail"],
            "TimeoutError: DVT request timed out",
        )
        self.assertEqual(failed["requestID"], "clear-1")
        self.assertEqual(succeeded, {"requestID": "clear-2", "ok": True})
        self.assertEqual(self.backend.clear_calls, 1)

    async def test_ping_does_not_mutate_location(self) -> None:
        response, should_shutdown = await self.processor.handle_line(
            '{"requestID":"ping-1","command":"ping"}'
        )

        self.assertEqual(response, {"requestID": "ping-1", "ok": True})
        self.assertFalse(should_shutdown)
        self.assertEqual(self.backend.set_calls, [])
        self.assertEqual(self.backend.clear_calls, 0)

    async def test_shutdown_acknowledges_before_ending_loop(self) -> None:
        response, should_shutdown = await self.processor.handle_line(
            '{"requestID":"shutdown-1","command":"shutdown"}'
        )

        self.assertEqual(response, {"requestID": "shutdown-1", "ok": True})
        self.assertTrue(should_shutdown)

    async def test_non_object_and_missing_request_id_are_rejected(self) -> None:
        non_object, _ = await self.processor.handle_line("[]")
        missing_id, _ = await self.processor.handle_line('{"command":"ping"}')

        self.assertEqual(non_object["error"]["code"], "invalid-message")
        self.assertEqual(missing_id["error"]["code"], "invalid-request-id")


if __name__ == "__main__":
    unittest.main()
