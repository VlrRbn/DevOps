import json
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))

from lambda_function import (  # noqa: E402
    IdempotencyConflict,
    IdempotencyInProgress,
    complete_claim,
    parse_event,
    payload_hash,
    process_event,
)


class ConditionalFailure(Exception):
    response = {"Error": {"Code": "ConditionalCheckFailedException"}}


class FakeTable:
    """Small in-memory substitute for the DynamoDB calls used by the handler."""

    def __init__(self) -> None:
        self.items: dict[str, dict[str, object]] = {}

    def put_item(self, **kwargs: object) -> None:
        item = dict(kwargs["Item"])  # type: ignore[arg-type]
        key = str(item["idempotency_key"])
        now = int(kwargs["ExpressionAttributeValues"][":now"])  # type: ignore[index]
        existing = self.items.get(key)
        if existing is not None and int(existing["expires_at"]) >= now:
            raise ConditionalFailure()
        self.items[key] = item

    def get_item(self, **kwargs: object) -> dict[str, object]:
        key = str(kwargs["Key"]["idempotency_key"])  # type: ignore[index]
        item = self.items.get(key)
        return {"Item": dict(item)} if item is not None else {}

    def update_item(self, **kwargs: object) -> None:
        key = str(kwargs["Key"]["idempotency_key"])  # type: ignore[index]
        values = kwargs["ExpressionAttributeValues"]  # type: ignore[assignment]
        item = self.items[key]
        if (
            item["status"] != values[":in_progress"]
            or item["payload_hash"] != values[":payload_hash"]
            or item["owner_token"] != values[":owner_token"]
        ):
            raise ConditionalFailure()
        item.update(
            {
                "status": values[":completed"],
                "result_json": values[":result_json"],
                "updated_at": values[":now"],
                "expires_at": values[":expires_at"],
            }
        )


class FakeContext:
    aws_request_id = "request-1"


EVENT = {
    "idempotency_key": "report-2026-08-customer-42",
    "customer_id": "customer-42",
    "report_date": "2026-08-01",
}


class IdempotencyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.table = FakeTable()

    def invoke(
        self,
        event: object,
        processor: Mock | None = None,
    ) -> dict[str, str]:
        if processor is None:
            processor = Mock(
                return_value={
                    "report_id": "report-123",
                    "customer_id": "customer-42",
                    "report_date": "2026-08-01",
                    "status": "generated",
                }
            )
        return process_event(
            event,
            FakeContext(),
            self.table,
            now_epoch=1_000,
            claim_ttl_seconds=300,
            record_ttl_seconds=86_400,
            processor=processor,
            owner_token="attempt-1",
        )

    def test_parse_event_rejects_non_object(self) -> None:
        with self.assertRaisesRegex(ValueError, "JSON object"):
            parse_event(None)

    def test_parse_event_requires_all_business_fields(self) -> None:
        with self.assertRaisesRegex(ValueError, "report_date"):
            parse_event(
                {
                    "idempotency_key": "key-1",
                    "customer_id": "customer-1",
                }
            )

    def test_payload_hash_is_stable_across_dictionary_order(self) -> None:
        reordered = {
            "report_date": EVENT["report_date"],
            "idempotency_key": EVENT["idempotency_key"],
            "customer_id": EVENT["customer_id"],
        }
        self.assertEqual(payload_hash(EVENT), payload_hash(reordered))

    def test_first_invocation_processes_and_completes_record(self) -> None:
        processor = Mock(
            return_value={
                "report_id": "report-123",
                "customer_id": "customer-42",
                "report_date": "2026-08-01",
                "status": "generated",
            }
        )

        result = self.invoke(EVENT, processor)

        self.assertEqual(result["idempotency_status"], "PROCESSED")
        processor.assert_called_once()
        record = self.table.items[EVENT["idempotency_key"]]
        self.assertEqual(record["status"], "COMPLETED")
        self.assertEqual(
            json.loads(str(record["result_json"]))["report_id"],
            "report-123",
        )

    def test_duplicate_replays_result_without_processing_again(self) -> None:
        processor = Mock(
            return_value={
                "report_id": "report-123",
                "customer_id": "customer-42",
                "report_date": "2026-08-01",
                "status": "generated",
            }
        )
        first = self.invoke(EVENT, processor)
        second = self.invoke(EVENT, processor)

        self.assertEqual(first["report_id"], second["report_id"])
        self.assertEqual(second["idempotency_status"], "REPLAYED")
        processor.assert_called_once()

    def test_same_key_with_different_payload_is_rejected(self) -> None:
        self.invoke(EVENT)
        conflicting = {**EVENT, "customer_id": "customer-99"}

        with self.assertRaises(IdempotencyConflict):
            self.invoke(conflicting)

    def test_live_in_progress_claim_is_rejected(self) -> None:
        self.table.items[EVENT["idempotency_key"]] = {
            "idempotency_key": EVENT["idempotency_key"],
            "status": "IN_PROGRESS",
            "payload_hash": payload_hash(EVENT),
            "owner_token": "another-request",
            "expires_at": 1_200,
        }

        with self.assertRaises(IdempotencyInProgress):
            self.invoke(EVENT)

    def test_expired_claim_can_be_reacquired(self) -> None:
        self.table.items[EVENT["idempotency_key"]] = {
            "idempotency_key": EVENT["idempotency_key"],
            "status": "IN_PROGRESS",
            "payload_hash": payload_hash(EVENT),
            "owner_token": "dead-request",
            "expires_at": 999,
        }

        result = self.invoke(EVENT)

        self.assertEqual(result["idempotency_status"], "PROCESSED")
        self.assertEqual(
            self.table.items[EVENT["idempotency_key"]]["owner_token"],
            "attempt-1",
        )

    def test_process_event_generates_attempt_owner_token(self) -> None:
        with patch("lambda_function.uuid4", return_value="generated-attempt-token"):
            process_event(
                EVENT,
                FakeContext(),
                self.table,
                now_epoch=1_000,
                claim_ttl_seconds=300,
                record_ttl_seconds=86_400,
            )

        self.assertEqual(
            self.table.items[EVENT["idempotency_key"]]["owner_token"],
            "generated-attempt-token",
        )

    def test_processor_failure_leaves_claim_in_progress(self) -> None:
        processor = Mock(side_effect=RuntimeError("business action failed"))

        with self.assertRaisesRegex(RuntimeError, "business action failed"):
            self.invoke(EVENT, processor)

        self.assertEqual(
            self.table.items[EVENT["idempotency_key"]]["status"],
            "IN_PROGRESS",
        )

    def test_stale_owner_cannot_complete_reclaimed_record(self) -> None:
        digest = payload_hash(EVENT)
        self.table.items[EVENT["idempotency_key"]] = {
            "idempotency_key": EVENT["idempotency_key"],
            "status": "IN_PROGRESS",
            "payload_hash": digest,
            "owner_token": "new-owner",
            "expires_at": 1_300,
        }

        with self.assertRaises(ConditionalFailure):
            complete_claim(
                self.table,
                EVENT["idempotency_key"],
                digest,
                "stale-owner",
                {"status": "generated"},
                now_epoch=1_000,
                record_ttl_seconds=86_400,
            )

    def test_completed_record_requires_object_result(self) -> None:
        self.table.items[EVENT["idempotency_key"]] = {
            "idempotency_key": EVENT["idempotency_key"],
            "status": "COMPLETED",
            "payload_hash": payload_hash(EVENT),
            "owner_token": "finished-owner",
            "result_json": "[]",
            "expires_at": 2_000,
        }

        with self.assertRaisesRegex(RuntimeError, "invalid result"):
            self.invoke(EVENT)


if __name__ == "__main__":
    unittest.main()
