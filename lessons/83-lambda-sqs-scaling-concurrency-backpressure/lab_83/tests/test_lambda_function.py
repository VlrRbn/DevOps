import json
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

from lambda_function import (  # noqa: E402
    MessageContractError,
    parse_record,
    perform_work,
    process_batch,
)


def sqs_record(message_id: str, task_id: str, work_seconds: object) -> dict[str, str]:
    return {
        "messageId": message_id,
        "body": json.dumps(
            {"task_id": task_id, "work_seconds": work_seconds}
        ),
    }


class SqsScalingConsumerTests(unittest.TestCase):
    def test_parse_record_accepts_bounded_work_item(self) -> None:
        message_id, item = parse_record(sqs_record("message-1", "task-1", 2.5))

        self.assertEqual(message_id, "message-1")
        self.assertEqual(item, {"task_id": "task-1", "work_seconds": 2.5})

    def test_parse_record_rejects_boolean_work_seconds(self) -> None:
        with self.assertRaisesRegex(MessageContractError, "between 0 and 10"):
            parse_record(sqs_record("message-1", "task-1", True))

    def test_parse_record_rejects_excessive_work_seconds(self) -> None:
        with self.assertRaisesRegex(MessageContractError, "between 0 and 10"):
            parse_record(sqs_record("message-1", "task-1", 11))

    def test_perform_work_uses_injected_sleeper(self) -> None:
        sleeper = Mock()

        result = perform_work(
            {"task_id": "task-1", "work_seconds": 3.0},
            sleeper=sleeper,
        )

        sleeper.assert_called_once_with(3.0)
        self.assertEqual(result["status"], "completed")

    def test_successful_batch_returns_no_failures(self) -> None:
        processor = Mock(
            return_value={
                "task_id": "task-1",
                "result_id": "result-1",
                "status": "completed",
            }
        )

        result = process_batch(
            {"Records": [sqs_record("message-1", "task-1", 1)]},
            request_id="request-1",
            processor=processor,
        )

        self.assertEqual(result, {"batchItemFailures": []})
        processor.assert_called_once()

    def test_processor_error_isolated_to_one_record(self) -> None:
        processor = Mock(
            side_effect=[
                {
                    "task_id": "task-1",
                    "result_id": "result-1",
                    "status": "completed",
                },
                RuntimeError("boom"),
            ]
        )
        result = process_batch(
            {
                "Records": [
                    sqs_record("message-1", "task-1", 1),
                    sqs_record("message-2", "task-2", 1),
                ]
            },
            request_id="request-1",
            processor=processor,
        )

        self.assertEqual(
            result,
            {"batchItemFailures": [{"itemIdentifier": "message-2"}]},
        )

    def test_missing_message_id_fails_whole_invocation(self) -> None:
        with self.assertRaisesRegex(MessageContractError, "messageId"):
            process_batch(
                {"Records": [{"body": "{}"}]},
                request_id="request-1",
            )

    def test_non_sqs_event_is_rejected(self) -> None:
        with self.assertRaisesRegex(MessageContractError, "Records"):
            process_batch({"task_id": "task-1"}, request_id="request-1")


if __name__ == "__main__":
    unittest.main()
