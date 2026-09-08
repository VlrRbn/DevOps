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
    PlannedConsumerError,
    RoutedEvent,
    parse_record,
    process_batch,
    process_event,
)

EXPECTED_SOURCE = "com.devops.orders"


def sqs_record(
    message_id: str,
    event_id: str,
    event_type: str = "Order Created",
    *,
    source: str = EXPECTED_SOURCE,
    amount: float = 150.0,
    fail_consumer: str | None = None,
) -> dict[str, object]:
    envelope = {
        "version": "0",
        "id": f"eventbridge-{event_id}",
        "detail-type": event_type,
        "source": source,
        "account": "123456789012",
        "time": "2026-09-06T12:00:00Z",
        "region": "eu-west-1",
        "resources": [],
        "detail": {
            "event_id": event_id,
            "order_id": "order-100",
            "amount": amount,
            "fail_consumer": fail_consumer,
        },
    }
    return {"messageId": message_id, "body": json.dumps(envelope)}


def completed_result(event: RoutedEvent, consumer_name: str) -> ConsumerResult:
    return {
        "event_id": event["event_id"],
        "event_type": event["event_type"],
        "consumer_name": consumer_name,
        "result_id": "result-1",
        "status": "completed",
    }


class EventBridgeConsumerTests(unittest.TestCase):
    def test_parse_record_reads_eventbridge_envelope(self) -> None:
        message_id, event = parse_record(
            sqs_record("message-1", "event-1"),
            EXPECTED_SOURCE,
        )

        self.assertEqual(message_id, "message-1")
        self.assertEqual(event["event_id"], "event-1")
        self.assertEqual(event["event_type"], "Order Created")
        self.assertEqual(event["amount"], 150.0)

    def test_parse_record_rejects_unexpected_source(self) -> None:
        with self.assertRaisesRegex(EventContractError, "source"):
            parse_record(
                sqs_record("message-1", "event-1", source="com.example.wrong"),
                EXPECTED_SOURCE,
            )

    def test_parse_record_rejects_invalid_detail(self) -> None:
        record = sqs_record("message-1", "event-1")
        envelope = json.loads(str(record["body"]))
        envelope["detail"]["amount"] = True
        record["body"] = json.dumps(envelope)

        with self.assertRaisesRegex(EventContractError, "amount"):
            parse_record(record, EXPECTED_SOURCE)

    def test_process_event_completes_for_unrelated_consumer(self) -> None:
        _, event = parse_record(
            sqs_record(
                "message-1",
                "event-1",
                fail_consumer="high_value",
            ),
            EXPECTED_SOURCE,
        )

        result = process_event(event, "audit")

        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["consumer_name"], "audit")

    def test_process_event_raises_only_for_selected_consumer(self) -> None:
        _, event = parse_record(
            sqs_record(
                "message-1",
                "event-1",
                fail_consumer="high_value",
            ),
            EXPECTED_SOURCE,
        )

        with self.assertRaises(PlannedConsumerError):
            process_event(event, "high_value")

    def test_successful_batch_returns_no_failures(self) -> None:
        processor = Mock(side_effect=completed_result)
        event = {
            "Records": [
                sqs_record("message-1", "event-1"),
                sqs_record("message-2", "event-2", "Order Refunded"),
            ]
        }

        response = process_batch(
            event,
            "request-1",
            "audit",
            EXPECTED_SOURCE,
            processor,
        )

        self.assertEqual(response, {"batchItemFailures": []})
        self.assertEqual(processor.call_count, 2)

    def test_standard_queue_continues_after_one_record_fails(self) -> None:
        def fail_first(event: RoutedEvent, consumer_name: str) -> ConsumerResult:
            if event["event_id"] == "event-1":
                raise RuntimeError("boom")
            return completed_result(event, consumer_name)

        processor = Mock(side_effect=fail_first)
        event = {
            "Records": [
                sqs_record("message-1", "event-1"),
                sqs_record("message-2", "event-2"),
            ]
        }

        response = process_batch(
            event,
            "request-1",
            "high_value",
            EXPECTED_SOURCE,
            processor,
        )

        self.assertEqual(
            response,
            {"batchItemFailures": [{"itemIdentifier": "message-1"}]},
        )
        self.assertEqual(processor.call_count, 2)

    def test_invalid_record_returns_only_its_identifier(self) -> None:
        invalid = sqs_record("message-1", "event-1")
        invalid["body"] = "not-json"
        event = {
            "Records": [
                invalid,
                sqs_record("message-2", "event-2"),
            ]
        }

        response = process_batch(
            event,
            "request-1",
            "audit",
            EXPECTED_SOURCE,
        )

        self.assertEqual(
            response,
            {"batchItemFailures": [{"itemIdentifier": "message-1"}]},
        )

    def test_missing_message_id_fails_before_business_processing(self) -> None:
        processor = Mock(side_effect=completed_result)
        event = {"Records": [{"body": "{}"}]}

        with self.assertRaisesRegex(EventContractError, "messageId"):
            process_batch(
                event,
                "request-1",
                "audit",
                EXPECTED_SOURCE,
                processor,
            )

        processor.assert_not_called()


if __name__ == "__main__":
    unittest.main()
