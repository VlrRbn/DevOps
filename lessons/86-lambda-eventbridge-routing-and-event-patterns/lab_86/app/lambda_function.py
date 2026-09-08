import hashlib
import json
import logging
from collections.abc import Callable
from typing import TypedDict, cast

logger = logging.getLogger()
logger.setLevel(logging.INFO)


class EventContractError(ValueError):
    """An EventBridge event delivered through SQS violates the lab contract."""


class PlannedConsumerError(RuntimeError):
    """A deterministic branch failure used by the isolation drill."""


class RoutedEvent(TypedDict):
    """Validated business event extracted from the EventBridge envelope."""

    event_id: str
    event_type: str
    order_id: str
    amount: float
    fail_consumer: str | None


class ConsumerResult(TypedDict):
    """Result produced by one routing branch after successful processing."""

    event_id: str
    event_type: str
    consumer_name: str
    result_id: str
    status: str


class BatchItemFailure(TypedDict):
    """One failed SQS record returned to the event source mapping."""

    itemIdentifier: str


class BatchResponse(TypedDict):
    """Partial batch response for a standard SQS source queue."""

    batchItemFailures: list[BatchItemFailure]


Processor = Callable[[RoutedEvent, str], ConsumerResult]


def require_string_keyed_dict(value: object, error_message: str) -> dict[str, object]:
    """Validate an external value before treating it as a JSON object."""
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise EventContractError(error_message)
    return cast(dict[str, object], value)


def get_message_id(record: object) -> str:
    """Extract the SQS identifier required by ReportBatchItemFailures."""
    record_object = require_string_keyed_dict(
        record,
        "SQS record must be an object with string keys",
    )
    message_id = record_object.get("messageId")
    if not isinstance(message_id, str) or not message_id.strip():
        raise EventContractError("SQS record must contain a non-empty messageId")
    return message_id.strip()


def parse_record(record: object, expected_source: str) -> tuple[str, RoutedEvent]:
    """Validate one EventBridge envelope transported in an SQS body."""
    record_object = require_string_keyed_dict(
        record,
        "SQS record must be an object with string keys",
    )
    message_id = get_message_id(record_object)
    raw_body = record_object.get("body")
    if not isinstance(raw_body, str):
        raise EventContractError("SQS record body must be a JSON string")

    try:
        decoded_body = cast(object, json.loads(raw_body))
    except json.JSONDecodeError as error:
        raise EventContractError("SQS record body must contain valid JSON") from error

    envelope = require_string_keyed_dict(
        decoded_body,
        "EventBridge envelope must be an object with string keys",
    )
    envelope_id = envelope.get("id")
    source = envelope.get("source")
    event_type = envelope.get("detail-type")
    detail = require_string_keyed_dict(
        envelope.get("detail"),
        "EventBridge detail must be an object with string keys",
    )

    if not isinstance(envelope_id, str) or not envelope_id.strip():
        raise EventContractError("EventBridge envelope id must be non-empty")
    if source != expected_source:
        raise EventContractError(f"EventBridge source must be {expected_source}")
    if event_type not in {"Order Created", "Order Refunded"}:
        raise EventContractError("detail-type must be Order Created or Order Refunded")

    event_id = detail.get("event_id")
    order_id = detail.get("order_id")
    amount = detail.get("amount")
    fail_consumer = detail.get("fail_consumer")

    if not isinstance(event_id, str) or not event_id.strip():
        raise EventContractError("detail.event_id must be a non-empty string")
    if not isinstance(order_id, str) or not order_id.strip():
        raise EventContractError("detail.order_id must be a non-empty string")
    if isinstance(amount, bool) or not isinstance(amount, (int, float)) or amount < 0:
        raise EventContractError("detail.amount must be a non-negative number")
    if fail_consumer is not None and fail_consumer not in {"audit", "high_value"}:
        raise EventContractError(
            "detail.fail_consumer must be null, audit, or high_value"
        )

    return message_id, {
        "event_id": event_id.strip(),
        "event_type": cast(str, event_type),
        "order_id": order_id.strip(),
        "amount": float(amount),
        "fail_consumer": cast(str | None, fail_consumer),
    }


def process_event(event: RoutedEvent, consumer_name: str) -> ConsumerResult:
    """Run one branch or raise the deterministic failure requested by the event."""
    if event["fail_consumer"] == consumer_name:
        raise PlannedConsumerError(
            f"planned failure for consumer={consumer_name} event={event['event_id']}"
        )

    result_source = f"{consumer_name}:{event['event_id']}:{event['event_type']}"
    return {
        "event_id": event["event_id"],
        "event_type": event["event_type"],
        "consumer_name": consumer_name,
        "result_id": hashlib.sha256(result_source.encode("utf-8")).hexdigest()[:12],
        "status": "completed",
    }


def process_batch(
    event: object,
    request_id: str,
    consumer_name: str,
    expected_source: str,
    processor: Processor = process_event,
) -> BatchResponse:
    """Process standard-queue records independently and return only failures."""
    event_object = require_string_keyed_dict(
        event,
        "event must be an SQS event object with string keys",
    )
    records_value = event_object.get("Records")
    if not isinstance(records_value, list):
        raise EventContractError("event.Records must be a list")
    records = cast(list[object], records_value)

    # Validate all transport IDs before business work. A record without an ID
    # cannot be represented safely in a partial batch response.
    message_ids = [get_message_id(record) for record in records]
    failures: list[BatchItemFailure] = []

    logger.info(
        json.dumps(
            {
                "event": "batch_started",
                "request_id": request_id,
                "consumer_name": consumer_name,
                "record_count": len(records),
            }
        )
    )

    for record, message_id in zip(records, message_ids):
        try:
            _, routed_event = parse_record(record, expected_source)
            logger.info(
                json.dumps(
                    {
                        "event": "routed_event_started",
                        "request_id": request_id,
                        "consumer_name": consumer_name,
                        "message_id": message_id,
                        "event_id": routed_event["event_id"],
                        "event_type": routed_event["event_type"],
                    }
                )
            )
            result = processor(routed_event, consumer_name)
            logger.info(
                json.dumps(
                    {
                        "event": "routed_event_completed",
                        "request_id": request_id,
                        "message_id": message_id,
                        **result,
                    }
                )
            )
        except Exception as error:
            failures.append({"itemIdentifier": message_id})
            logger.error(
                json.dumps(
                    {
                        "event": "routed_event_failed",
                        "request_id": request_id,
                        "consumer_name": consumer_name,
                        "message_id": message_id,
                        "error_type": type(error).__name__,
                        "error": str(error),
                    }
                )
            )

    return {"batchItemFailures": failures}


def lambda_handler(event: object, context: object) -> BatchResponse:
    """AWS Lambda entry point shared by the audit and high-value functions."""
    import os

    consumer_name = os.environ.get("CONSUMER_NAME", "local")
    expected_source = os.environ.get("EXPECTED_EVENT_SOURCE", "com.devops.orders")
    request_id = getattr(context, "aws_request_id", "local-request")
    if not isinstance(request_id, str) or not request_id.strip():
        request_id = "local-request"
    return process_batch(
        event,
        request_id,
        consumer_name,
        expected_source,
    )
