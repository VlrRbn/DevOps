import json
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

from lambda_function import (  # noqa: E402
    FifoWorkItem,
    MessageContractError,
    PlannedWorkError,
    WorkResult,
    parse_record,
    perform_work,
    process_fifo_batch,
)


def fifo_record(
    message_id: str,
    group_id: str,
    sequence: int,
    *,
    should_fail: bool = False,
    work_seconds: object = 0,
) -> dict[str, object]:
    return {
        "messageId": message_id,
        "body": json.dumps(
            {
                "task_id": f"{group_id}-task-{sequence}",
                "sequence": sequence,
                "work_seconds": work_seconds,
                "should_fail": should_fail,
            }
        ),
        "attributes": {
            "MessageGroupId": group_id,
            "MessageDeduplicationId": f"{group_id}-dedup-{sequence}",
            "SequenceNumber": str(sequence),
        },
    }


def completed_result(item: FifoWorkItem) -> WorkResult:
    return {
        "task_id": item["task_id"],
        "group_id": item["group_id"],
        "sequence": item["sequence"],
        "result_id": "result-1",
        "status": "completed",
    }


class FifoConsumerTests(unittest.TestCase):
    def test_parse_record_reads_fifo_attributes_and_body(self) -> None:
        message_id, item = parse_record(fifo_record("message-1", "group-a", 1))

        self.assertEqual(message_id, "message-1")
        self.assertEqual(item["group_id"], "group-a")
        self.assertEqual(item["sequence"], 1)
        self.assertEqual(item["deduplication_id"], "group-a-dedup-1")

    def test_parse_record_rejects_missing_message_group(self) -> None:
        record = fifo_record("message-1", "group-a", 1)
        record["attributes"] = {"MessageDeduplicationId": "dedup-1"}

        with self.assertRaisesRegex(MessageContractError, "MessageGroupId"):
            parse_record(record)

    def test_perform_work_uses_injected_sleeper(self) -> None:
        sleeper = Mock()
        _, item = parse_record(
            fifo_record("message-1", "group-a", 1, work_seconds=2.5)
        )

        result = perform_work(item, sleeper=sleeper)

        sleeper.assert_called_once_with(2.5)
        self.assertEqual(result["status"], "completed")

    def test_perform_work_raises_planned_failure(self) -> None:
        _, item = parse_record(
            fifo_record("message-1", "group-a", 1, should_fail=True)
        )

        with self.assertRaises(PlannedWorkError):
            perform_work(item)

    def test_successful_batch_processes_every_record_in_order(self) -> None:
        processor = Mock(side_effect=completed_result)
        event = {
            "Records": [
                fifo_record("message-1", "group-a", 1),
                fifo_record("message-2", "group-a", 2),
                fifo_record("message-3", "group-a", 3),
            ]
        }

        response = process_fifo_batch(event, "request-1", processor=processor)

        self.assertEqual(response, {"batchItemFailures": []})
        self.assertEqual(
            [call.args[0]["sequence"] for call in processor.call_args_list],
            [1, 2, 3],
        )

    def test_first_failure_returns_failed_and_unprocessed_records(self) -> None:
        processor = Mock(
            side_effect=[
                {
                    "task_id": "group-a-task-1",
                    "group_id": "group-a",
                    "sequence": 1,
                    "result_id": "result-1",
                    "status": "completed",
                },
                RuntimeError("boom"),
            ]
        )
        event = {
            "Records": [
                fifo_record("message-1", "group-a", 1),
                fifo_record("message-2", "group-a", 2),
                fifo_record("message-3", "group-a", 3),
            ]
        }

        response = process_fifo_batch(event, "request-1", processor=processor)

        self.assertEqual(
            response,
            {
                "batchItemFailures": [
                    {"itemIdentifier": "message-2"},
                    {"itemIdentifier": "message-3"},
                ]
            },
        )
        self.assertEqual(processor.call_count, 2)

    def test_invalid_record_blocks_itself_and_later_records(self) -> None:
        invalid_record = fifo_record("message-2", "group-a", 2)
        invalid_record["body"] = "not-json"
        event = {
            "Records": [
                fifo_record("message-1", "group-a", 1),
                invalid_record,
                fifo_record("message-3", "group-a", 3),
            ]
        }

        response = process_fifo_batch(event, "request-1")

        self.assertEqual(
            response["batchItemFailures"],
            [
                {"itemIdentifier": "message-2"},
                {"itemIdentifier": "message-3"},
            ],
        )

    def test_missing_message_id_fails_before_business_processing(self) -> None:
        processor = Mock(side_effect=completed_result)
        event = {
            "Records": [
                fifo_record("message-1", "group-a", 1),
                {"body": "{}", "attributes": {}},
            ]
        }

        with self.assertRaisesRegex(MessageContractError, "messageId"):
            process_fifo_batch(event, "request-1", processor=processor)

        processor.assert_not_called()


if __name__ == "__main__":
    unittest.main()
