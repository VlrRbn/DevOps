import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

APP_DIR = Path(__file__).resolve().parents[1] / "app"
# Unit tests import the handler directly instead of packaging or invoking AWS.
sys.path.insert(0, str(APP_DIR))

from lambda_function import lambda_handler, parse_event  # noqa: E402


class FakeContext:
    # Lambda creates context in AWS; the unit test needs only the request ID.
    aws_request_id = "test-request-id"


class AsyncEventTests(unittest.TestCase):
    def test_parse_event_accepts_success_by_default(self) -> None:
        self.assertEqual(parse_event({"event_id": "evt-1"}), ("evt-1", "success"))

    def test_parse_event_rejects_non_object(self) -> None:
        with self.assertRaisesRegex(ValueError, "JSON object"):
            parse_event(None)

    def test_parse_event_requires_event_id(self) -> None:
        with self.assertRaisesRegex(ValueError, "event_id"):
            parse_event({"mode": "success"})

    def test_parse_event_rejects_unknown_mode(self) -> None:
        with self.assertRaisesRegex(ValueError, "mode must be"):
            parse_event({"event_id": "evt-1", "mode": "slow"})

    def test_handler_returns_processing_result(self) -> None:
        with (
            patch.dict(os.environ, {"APP_ENV": "test"}),
            self.assertLogs(level="INFO") as captured_logs,
        ):
            result = lambda_handler(
                {"event_id": "evt-success", "mode": "success"},
                FakeContext(),
            )

        self.assertEqual(
            result,
            {
                "status": "processed",
                "event_id": "evt-success",
                "environment": "test",
                "request_id": "test-request-id",
            },
        )
        self.assertTrue(
            any("async_event_processed" in line for line in captured_logs.output),
            "The successful path must emit an application completion record.",
        )

    def test_handler_raises_for_failure_mode(self) -> None:
        with (
            self.assertLogs(level="INFO") as captured_logs,
            self.assertRaisesRegex(RuntimeError, "evt-failure"),
        ):
            lambda_handler(
                {"event_id": "evt-failure", "mode": "fail"},
                FakeContext(),
            )

        self.assertFalse(
            any("async_event_processed" in line for line in captured_logs.output),
            "A failed attempt must not emit a successful completion record.",
        )


if __name__ == "__main__":
    unittest.main()
