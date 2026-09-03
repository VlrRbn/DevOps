import hashlib
import json
import logging
from collections.abc import Callable
from typing import TypedDict, cast

logger = logging.getLogger()
logger.setLevel(logging.INFO)


class EventContractError(ValueError):
    """An SNS-to-SQS event does not satisfy the lab contract."""


class PlannedConsumerError(RuntimeError):
    """A deterministic branch failure used by the isolation drill."""


class FanoutEvent(TypedDict):
    """Validated business event delivered through one fan-out branch."""

    event_id: str
    event_type: str
    order_id: str
    amount: float
    fail_consumer: str | None


class ConsumerResult(TypedDict):
    """Result produced by one branch after successful processing."""

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


Processor = Callable[[FanoutEvent, str], ConsumerResult]


def require_string_keyed_dict(value: object, error_message: str) -> dict[str, object]:
    """Validate an external value before using it as a JSON-style object."""
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise EventContractError(error_message)
    return cast(dict[str, object], value)


def get_message_id(record: object) -> str:
    """Extract the transport identifier needed by batchItemFailures."""
    record_object = require_string_keyed_dict(
        record,
        "SQS record must be an object with string keys",
    )
    message_id = record_object.get("messageId")
    if not isinstance(message_id, str) or not message_id.strip():
        raise EventContractError("SQS record must contain a non-empty messageId")
    return message_id.strip()


def get_event_type_attribute(record: dict[str, object]) -> str:
    """Read the SNS event_type attribute preserved by raw SQS delivery."""
    attributes = require_string_keyed_dict(
        record.get("messageAttributes"),
        "SQS record messageAttributes must be an object",
    )
    event_type_attribute = require_string_keyed_dict(
        attributes.get("event_type"),
        "messageAttributes.event_type must be an object",
    )
    event_type = event_type_attribute.get("stringValue")
    data_type = event_type_attribute.get("dataType")

    if data_type != "String":
        raise EventContractError("event_type message attribute must use String")
    if not isinstance(event_type, str) or not event_type.strip():
        raise EventContractError("event_type message attribute must be non-empty")
    return event_type.strip()


def parse_record(record: object) -> tuple[str, FanoutEvent]:
    """Validate one raw SNS message delivered through an SQS record."""
    record_object = require_string_keyed_dict(
        record,
        "SQS record must be an object with string keys",
    )
    message_id = get_message_id(record_object)
    attribute_event_type = get_event_type_attribute(record_object)

    raw_body = record_object.get("body")
    if not isinstance(raw_body, str):
        raise EventContractError("SQS record body must be a JSON string")

    try:
        decoded_body = cast(object, json.loads(raw_body))
    except json.JSONDecodeError as error:
        raise EventContractError("SQS record body must contain valid JSON") from error

    body = require_string_keyed_dict(
        decoded_body,
        "SNS message body must decode to an object with string keys",
    )
    event_id = body.get("event_id")
    event_type = body.get("event_type")
    order_id = body.get("order_id")
    amount = body.get("amount")
    fail_consumer = body.get("fail_consumer")

    if not isinstance(event_id, str) or not event_id.strip():
        raise EventContractError("event_id must be a non-empty string")
    if not isinstance(event_type, str) or not event_type.strip():
        raise EventContractError("event_type must be a non-empty string")
    if event_type.strip() != attribute_event_type:
        raise EventContractError("body event_type must match the SNS message attribute")
    if not isinstance(order_id, str) or not order_id.strip():
        raise EventContractError("order_id must be a non-empty string")
    if isinstance(amount, bool) or not isinstance(amount, (int, float)) or amount < 0:
        raise EventContractError("amount must be a non-negative number")
    if fail_consumer is not None and (
        not isinstance(fail_consumer, str) or not fail_consumer.strip()
    ):
        raise EventContractError("fail_consumer must be null or a non-empty string")

    return message_id, {
        "event_id": event_id.strip(),
        "event_type": event_type.strip(),
        "order_id": order_id.strip(),
        "amount": float(amount),
        "fail_consumer": fail_consumer.strip() if fail_consumer else None,
    }


def process_event(event: FanoutEvent, consumer_name: str) -> ConsumerResult:
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

    # Validate transport IDs before business work; an absent ID cannot be
    # represented safely in the partial batch response.
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
            _, business_event = parse_record(record)
            logger.info(
                json.dumps(
                    {
                        "event": "fanout_event_started",
                        "request_id": request_id,
                        "consumer_name": consumer_name,
                        "message_id": message_id,
                        "event_id": business_event["event_id"],
                        "event_type": business_event["event_type"],
                    }
                )
            )
            result = processor(business_event, consumer_name)
            logger.info(
                json.dumps(
                    {
                        "event": "fanout_event_completed",
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
                        "event": "fanout_event_failed",
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
    """AWS Lambda entry point shared by the audit and billing functions."""
    import os

    consumer_name = os.environ.get("CONSUMER_NAME", "local")
    request_id = getattr(context, "aws_request_id", "local-request")
    if not isinstance(request_id, str) or not request_id.strip():
        request_id = "local-request"
    return process_batch(event, request_id, consumer_name)
