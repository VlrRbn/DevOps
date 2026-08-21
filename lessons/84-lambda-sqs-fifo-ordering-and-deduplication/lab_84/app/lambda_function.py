import hashlib
import json
import logging
import time
from collections.abc import Callable
from typing import TypedDict, cast

logger = logging.getLogger()
logger.setLevel(logging.INFO)


class MessageContractError(ValueError):
    """An SQS FIFO record does not match the lab contract."""


class PlannedWorkError(RuntimeError):
    """A deterministic lab failure used to demonstrate an ordering barrier."""


class FifoWorkItem(TypedDict):
    """Validated business work plus the FIFO transport attributes."""

    task_id: str
    sequence: int
    work_seconds: float
    should_fail: bool
    group_id: str
    deduplication_id: str


class WorkResult(TypedDict):
    """Result of one successfully processed FIFO work item."""

    task_id: str
    group_id: str
    sequence: int
    result_id: str
    status: str


class BatchItemFailure(TypedDict):
    """One failed or intentionally unprocessed SQS record."""

    itemIdentifier: str


class BatchResponse(TypedDict):
    """Lambda partial batch response for the SQS event source mapping."""

    batchItemFailures: list[BatchItemFailure]


Processor = Callable[[FifoWorkItem], WorkResult]


def require_string_keyed_dict(value: object, error_message: str) -> dict[str, object]:
    """Validate an external object before treating it as a JSON-style mapping."""
    if not isinstance(value, dict) or not all(
        isinstance(key, str) for key in value
    ):
        raise MessageContractError(error_message)

    # Runtime validation above makes this cast the explicit trust boundary.
    return cast(dict[str, object], value)


def get_message_id(record: object) -> str:
    """Return a usable transport ID before any business work starts."""
    record_object = require_string_keyed_dict(
        record,
        "SQS record must be an object with string keys",
    )
    message_id = record_object.get("messageId")
    if not isinstance(message_id, str) or not message_id.strip():
        raise MessageContractError("SQS record must contain a non-empty messageId")
    return message_id.strip()


def parse_record(record: object) -> tuple[str, FifoWorkItem]:
    """Validate one SQS FIFO record and decode its work item."""
    record_object = require_string_keyed_dict(
        record,
        "SQS record must be an object with string keys",
    )
    message_id = get_message_id(record_object)

    attributes = require_string_keyed_dict(
        record_object.get("attributes"),
        "SQS FIFO record attributes must be an object with string keys",
    )
    group_id = attributes.get("MessageGroupId")
    deduplication_id = attributes.get("MessageDeduplicationId")

    if not isinstance(group_id, str) or not group_id.strip():
        raise MessageContractError("MessageGroupId must be a non-empty string")
    if not isinstance(deduplication_id, str) or not deduplication_id.strip():
        raise MessageContractError("MessageDeduplicationId must be a non-empty string")

    raw_body = record_object.get("body")
    if not isinstance(raw_body, str):
        raise MessageContractError("SQS record body must be a JSON string")

    try:
        decoded_body = cast(object, json.loads(raw_body))
    except json.JSONDecodeError as error:
        raise MessageContractError("SQS record body must contain valid JSON") from error

    body = require_string_keyed_dict(
        decoded_body,
        "SQS message body must decode to an object with string keys",
    )
    task_id = body.get("task_id")
    sequence = body.get("sequence")
    work_seconds = body.get("work_seconds")
    should_fail = body.get("should_fail")

    if not isinstance(task_id, str) or not task_id.strip():
        raise MessageContractError("task_id must be a non-empty string")
    if (
        isinstance(sequence, bool)
        or not isinstance(sequence, int)
        or sequence < 1
    ):
        raise MessageContractError("sequence must be a positive integer")
    if (
        isinstance(work_seconds, bool)
        or not isinstance(work_seconds, (int, float))
        or not 0 <= work_seconds <= 3
    ):
        raise MessageContractError("work_seconds must be a number between 0 and 3")
    if not isinstance(should_fail, bool):
        raise MessageContractError("should_fail must be a boolean")

    return message_id, {
        "task_id": task_id.strip(),
        "sequence": sequence,
        "work_seconds": float(work_seconds),
        "should_fail": should_fail,
        "group_id": group_id.strip(),
        "deduplication_id": deduplication_id.strip(),
    }


def perform_work(
    item: FifoWorkItem,
    sleeper: Callable[[float], None] = time.sleep,
) -> WorkResult:
    """Simulate bounded work or raise the requested deterministic failure."""
    if item["should_fail"]:
        raise PlannedWorkError(f"planned failure for {item['task_id']}")

    sleeper(item["work_seconds"])
    result_source = f"{item['group_id']}:{item['sequence']}:{item['task_id']}"
    return {
        "task_id": item["task_id"],
        "group_id": item["group_id"],
        "sequence": item["sequence"],
        "result_id": hashlib.sha256(result_source.encode("utf-8")).hexdigest()[:12],
        "status": "completed",
    }


def process_fifo_batch(
    event: object,
    request_id: str,
    processor: Processor = perform_work,
) -> BatchResponse:
    """Stop after the first failure and return every unprocessed record."""
    event_object = require_string_keyed_dict(
        event,
        "event must be an SQS event object with string keys",
    )
    records_value = event_object.get("Records")
    if not isinstance(records_value, list):
        raise MessageContractError("event.Records must be a list")
    records = cast(list[object], records_value)

    # Validate every transport ID before producing any business side effect.
    # A missing ID cannot be represented safely in batchItemFailures.
    message_ids = [get_message_id(record) for record in records]

    logger.info(
        json.dumps(
            {
                "event": "batch_started",
                "request_id": request_id,
                "record_count": len(records),
            }
        )
    )

    failures: list[BatchItemFailure] = []
    for index, (record, message_id) in enumerate(zip(records, message_ids)):
        started_at = time.time()
        try:
            _, item = parse_record(record)
            logger.info(
                json.dumps(
                    {
                        "event": "work_started",
                        "request_id": request_id,
                        "message_id": message_id,
                        "group_id": item["group_id"],
                        "sequence": item["sequence"],
                        "task_id": item["task_id"],
                        "deduplication_id": item["deduplication_id"],
                    }
                )
            )
            result = processor(item)
            logger.info(
                json.dumps(
                    {
                        "event": "work_completed",
                        "request_id": request_id,
                        "message_id": message_id,
                        "group_id": result["group_id"],
                        "sequence": result["sequence"],
                        "task_id": result["task_id"],
                        "result_id": result["result_id"],
                        "elapsed_ms": round((time.time() - started_at) * 1000),
                    }
                )
            )
        except Exception as error:
            # Returning the untouched tail preserves FIFO order. When SQS
            # delivers that tail again, each record's receive count increases,
            # so a valid record can reach the DLQ with the poison record.
            failed_and_unprocessed = message_ids[index:]
            logger.error(
                json.dumps(
                    {
                        "event": "work_failed",
                        "request_id": request_id,
                        "message_id": message_id,
                        "error_type": type(error).__name__,
                        "error": str(error),
                        "returned_item_identifiers": failed_and_unprocessed,
                    }
                )
            )
            for deferred_message_id in message_ids[index + 1 :]:
                logger.warning(
                    json.dumps(
                        {
                            "event": "work_deferred_after_failure",
                            "request_id": request_id,
                            "message_id": deferred_message_id,
                            "blocked_by_message_id": message_id,
                        }
                    )
                )
            failures.extend(
                {"itemIdentifier": failed_message_id}
                for failed_message_id in failed_and_unprocessed
            )
            break

    logger.info(
        json.dumps(
            {
                "event": "batch_completed",
                "request_id": request_id,
                "record_count": len(records),
                "failure_count": len(failures),
            }
        )
    )
    return {"batchItemFailures": failures}


def lambda_handler(event: object, context: object) -> BatchResponse:
    """AWS Lambda entry point for the FIFO event source mapping."""
    request_id = "local-request"
    context_request_id = cast(
        object,
        getattr(context, "aws_request_id", None),
    )
    if isinstance(context_request_id, str) and context_request_id.strip():
        request_id = context_request_id

    return process_fifo_batch(event, request_id=request_id)
