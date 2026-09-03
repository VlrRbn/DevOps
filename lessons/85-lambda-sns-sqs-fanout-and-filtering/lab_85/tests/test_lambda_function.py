import json
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

from lambda_function import (  # noqa: E402
    ConsumerResult,
    EventContractError,
    FanoutEvent,
    PlannedConsumerError,
    parse_record,
    process_batch,
    process_event,
)


def sqs_record(
    message_id: str,
    event_id: str,
    event_type: str,
    *,
    fail_consumer: str | None = None,
    attribute_event_type: str | None = None,
) -> dict[str, object]:
    return {
        "messageId": message_id,
        "body": json.dumps(
            {
                "event_id": event_id,
                "event_type": event_type,
                "order_id": "order-100",
                "amount": 42.5,
                "fail_consumer": fail_consumer,
            }
        ),
        "messageAttributes": {
            "event_type": {
                "stringValue": attribute_event_type or event_type,
                "dataType": "String",
            }
        },
    }


def completed_result(event: FanoutEvent, consumer_name: str) -> ConsumerResult:
    return {
        "event_id": event["event_id"],
        "event_type": event["event_type"],
        "consumer_name": consumer_name,
        "result_id": "result-1",
        "status": "completed",
    }


class FanoutConsumerTests(unittest.TestCase):
    def test_parse_record_reads_raw_body_and_message_attribute(self) -> None:
        message_id, event = parse_record(
            sqs_record("message-1", "event-1", "order.created")
        )

        self.assertEqual(message_id, "message-1")
        self.assertEqual(event["event_id"], "event-1")
        self.assertEqual(event["event_type"], "order.created")
        self.assertEqual(event["amount"], 42.5)

    def test_parse_record_rejects_attribute_body_mismatch(self) -> None:
        record = sqs_record(
            "message-1",
            "event-1",
            "order.created",
            attribute_event_type="profile.updated",
        )

        with self.assertRaisesRegex(EventContractError, "must match"):
            parse_record(record)

    def test_process_event_completes_for_unrelated_consumer(self) -> None:
        _, event = parse_record(
            sqs_record(
                "message-1",
                "event-1",
                "order.created",
                fail_consumer="billing",
            )
        )

        result = process_event(event, "audit")

        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["consumer_name"], "audit")

    def test_process_event_raises_only_for_selected_consumer(self) -> None:
        _, event = parse_record(
            sqs_record(
                "message-1",
                "event-1",
                "order.created",
                fail_consumer="billing",
            )
        )

        with self.assertRaises(PlannedConsumerError):
            process_event(event, "billing")

    def test_successful_batch_returns_no_failures(self) -> None:
        processor = Mock(side_effect=completed_result)
        event = {
            "Records": [
                sqs_record("message-1", "event-1", "order.created"),
                sqs_record("message-2", "event-2", "order.refunded"),
            ]
        }

        response = process_batch(event, "request-1", "audit", processor)

        self.assertEqual(response, {"batchItemFailures": []})
        self.assertEqual(processor.call_count, 2)

    def test_standard_queue_continues_after_one_record_fails(self) -> None:
        def fail_first(event: FanoutEvent, consumer_name: str) -> ConsumerResult:
            if event["event_id"] == "event-1":
                raise RuntimeError("boom")
            return completed_result(event, consumer_name)

        processor = Mock(side_effect=fail_first)
        event = {
            "Records": [
                sqs_record("message-1", "event-1", "order.created"),
                sqs_record("message-2", "event-2", "order.refunded"),
            ]
        }

        response = process_batch(event, "request-1", "billing", processor)

        self.assertEqual(
            response,
            {"batchItemFailures": [{"itemIdentifier": "message-1"}]},
        )
        self.assertEqual(processor.call_count, 2)

    def test_invalid_record_returns_only_its_identifier(self) -> None:
        invalid = sqs_record("message-1", "event-1", "order.created")
        invalid["body"] = "not-json"
        event = {
            "Records": [
                invalid,
                sqs_record("message-2", "event-2", "order.created"),
            ]
        }

        response = process_batch(event, "request-1", "audit")

        self.assertEqual(
            response,
            {"batchItemFailures": [{"itemIdentifier": "message-1"}]},
        )

    def test_missing_message_id_fails_before_business_processing(self) -> None:
        processor = Mock(side_effect=completed_result)
        event = {"Records": [{"body": "{}", "messageAttributes": {}}]}

        with self.assertRaisesRegex(EventContractError, "messageId"):
            process_batch(event, "request-1", "audit", processor)

        processor.assert_not_called()


if __name__ == "__main__":
    unittest.main()
