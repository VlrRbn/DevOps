import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

APP_DIR = Path(__file__).resolve().parents[1] / "app"
# Unit tests import the handler directly instead of packaging or invoking AWS.
sys.path.insert(0, str(APP_DIR))

from lambda_function import build_greeting, lambda_handler  # noqa: E402


class FakeContext:
    # Lambda creates context in production. The handler only needs this one
    # attribute, so the test uses a minimal substitute.
    aws_request_id = "test-request-id"


class GreetingTests(unittest.TestCase):
    def test_build_greeting(self) -> None:
        # Business logic stays testable without an event or Lambda runtime.
        self.assertEqual(build_greeting(" Valerii "), "Hello, Valerii!")

    def test_build_greeting_rejects_non_string(self) -> None:
        with self.assertRaisesRegex(ValueError, "name must be a string"):
            build_greeting(42)  # type: ignore[arg-type]

    def test_build_greeting_rejects_blank_name(self) -> None:
        with self.assertRaisesRegex(ValueError, "name must not be empty"):
            build_greeting("   ")

    def test_handler_uses_default_name(self) -> None:
        # patch.dict prevents the test from depending on the developer's shell.
        with patch.dict(os.environ, {"APP_ENV": "test"}):
            result = lambda_handler({}, FakeContext())

        self.assertEqual(result["message"], "Hello, world!")
        self.assertEqual(result["environment"], "test")
        self.assertEqual(result["request_id"], "test-request-id")

    def test_handler_rejects_non_object_event(self) -> None:
        # A valid JSON document is not necessarily a JSON object.
        with self.assertRaisesRegex(ValueError, "event must be a JSON object"):
            lambda_handler(None, FakeContext())

    def test_handler_returns_expected_shape(self) -> None:
        # Keep the response contract stable for an eventual event source or API.
        result = lambda_handler({"name": "Lambda"}, FakeContext())

        self.assertEqual(
            set(result),
            {"message", "environment", "request_id"},
        )


if __name__ == "__main__":
    unittest.main()
