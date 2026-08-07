import json
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

from lambda_function import (  # noqa: E402
    MessageContractError,
    generate_report,
    parse_record,
    process_batch,
)


def sqs_record(message_id: str, body: object) -> dict[str, str]:
    return {"messageId": message_id, "body": json.dumps(body)}


VALID_BODY = {
    "task_id": "report-001",
    "action": "generate_report",
    "should_fail": False,
}


class SqsBatchTests(unittest.TestCase):
    def test_parse_record_accepts_valid_message(self) -> None:
        message_id, body = parse_record(sqs_record("message-1", VALID_BODY))

        self.assertEqual(message_id, "message-1")
        self.assertEqual(body["task_id"], "report-001")

    def test_parse_record_rejects_invalid_json(self) -> None:
        with self.assertRaisesRegex(MessageContractError, "valid JSON"):
            parse_record({"messageId": "message-1", "body": "{"})

    def test_parse_record_rejects_unknown_action(self) -> None:
        body = {**VALID_BODY, "action": "delete_everything"}

        with self.assertRaisesRegex(MessageContractError, "generate_report"):
            parse_record(sqs_record("message-1", body))

    def test_generate_report_is_deterministic(self) -> None:
        first = generate_report(VALID_BODY)
        second = generate_report(VALID_BODY)

        self.assertEqual(first, second)

    def test_successful_batch_returns_no_failures(self) -> None:
        result = process_batch(
            {"Records": [sqs_record("message-1", VALID_BODY)]}
        )

        self.assertEqual(result, {"batchItemFailures": []})

    def test_mixed_batch_reports_only_failed_record(self) -> None:
        poison = {**VALID_BODY, "task_id": "poison-001", "should_fail": True}
        result = process_batch(
            {
                "Records": [
                    sqs_record("message-ok", VALID_BODY),
                    sqs_record("message-bad", poison),
                ]
            }
        )

        self.assertEqual(
            result,
            {"batchItemFailures": [{"itemIdentifier": "message-bad"}]},
        )

    def test_processor_failure_isolated_to_one_record(self) -> None:
        processor = Mock(side_effect=[{"report_id": "abc"}, RuntimeError("boom")])
        result = process_batch(
            {
                "Records": [
                    sqs_record("message-1", VALID_BODY),
                    sqs_record("message-2", VALID_BODY),
                ]
            },
            processor=processor,
        )

        self.assertEqual(
            result,
            {"batchItemFailures": [{"itemIdentifier": "message-2"}]},
        )
        self.assertEqual(processor.call_count, 2)

    def test_missing_message_id_fails_whole_invocation(self) -> None:
        with self.assertRaisesRegex(MessageContractError, "messageId"):
            process_batch({"Records": [{"body": json.dumps(VALID_BODY)}]})

    def test_non_sqs_event_is_rejected(self) -> None:
        with self.assertRaisesRegex(MessageContractError, "Records"):
            process_batch({"task_id": "not-an-sqs-event"})


if __name__ == "__main__":
    unittest.main()
