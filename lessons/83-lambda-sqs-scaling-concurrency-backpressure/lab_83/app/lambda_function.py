import hashlib
import json
import logging
import time
from collections.abc import Callable
from typing import TypedDict, cast

logger = logging.getLogger()
logger.setLevel(logging.INFO)


class MessageContractError(ValueError):
    """An SQS record or its body does not match the lab contract."""


class WorkItem(TypedDict):
    """Validated unit of business work decoded from an SQS message body."""

    task_id: str
    work_seconds: float


class WorkResult(TypedDict):
    """Result produced after one work item has been processed."""

    task_id: str
    result_id: str
    status: str


class BatchItemFailure(TypedDict):
    """AWS partial batch response entry for one failed SQS message."""

    itemIdentifier: str


class BatchResponse(TypedDict):
    """Response contract required by Lambda partial batch failure handling."""

    batchItemFailures: list[BatchItemFailure]


Processor = Callable[[WorkItem], WorkResult]


def require_string_keyed_dict(value: object, error_message: str) -> dict[str, object]:
    """Validate that a value is a dict with string keys and return it."""
    if not isinstance(value, dict) or not all(
        isinstance(key, str) for key in value
    ):
        raise MessageContractError(error_message)

    # Runtime validation above makes this cast the explicit trust boundary.
    return cast(dict[str, object], value)


def parse_record(record: object) -> tuple[str, WorkItem]:
    """Validate one SQS record and return its transport ID and work item."""
    record_object = require_string_keyed_dict(
        record,
        "SQS record must be an object with string keys",
    )

    message_id = record_object.get("messageId")
    if not isinstance(message_id, str) or not message_id.strip():
        raise MessageContractError("SQS record must contain a non-empty messageId")

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
    work_seconds = body.get("work_seconds")

    if not isinstance(task_id, str) or not task_id.strip():
        raise MessageContractError("task_id must be a non-empty string")
    if (
        isinstance(work_seconds, bool)
        or not isinstance(work_seconds, (int, float))
        or not 0 <= work_seconds <= 10
    ):
        raise MessageContractError("work_seconds must be a number between 0 and 10")

    return message_id.strip(), {
        "task_id": task_id.strip(),
        "work_seconds": float(work_seconds),
    }


def perform_work(
    item: WorkItem,
    sleeper: Callable[[float], None] = time.sleep,
) -> WorkResult:
    """Simulate bounded work without calling an external dependency."""
    task_id = item["task_id"]
    sleeper(item["work_seconds"])
    return {
        "task_id": task_id,
        "result_id": hashlib.sha256(task_id.encode("utf-8")).hexdigest()[:12],
        "status": "completed",
    }


def process_batch(
    event: object,
    request_id: str,
    processor: Processor = perform_work,
) -> BatchResponse:
    """Process SQS records independently and report only failed message IDs."""
    event_object = require_string_keyed_dict(
        event,
        "event must be an SQS event object with string keys",
    )

    records_value = event_object.get("Records")
    if not isinstance(records_value, list):
        raise MessageContractError("event.Records must be a list")
    records = cast(list[object], records_value)

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
    for record in records:
        record_object = require_string_keyed_dict(
            record,
            "SQS record must be an object with string keys",
        )
        message_id = record_object.get("messageId")
        if not isinstance(message_id, str) or not message_id.strip():
            raise MessageContractError("SQS record must contain a non-empty messageId")

        started_at = time.time()
        try:
            _, item = parse_record(record_object)
            logger.info(
                json.dumps(
                    {
                        "event": "work_started",
                        "request_id": request_id,
                        "message_id": message_id,
                        "task_id": item["task_id"],
                        "work_seconds": item["work_seconds"],
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
                        "task_id": item["task_id"],
                        "result_id": result["result_id"],
                        "elapsed_ms": round((time.time() - started_at) * 1000),
                    }
                )
            )
        except Exception as error:
            logger.error(
                json.dumps(
                    {
                        "event": "work_failed",
                        "request_id": request_id,
                        "message_id": message_id,
                        "error_type": type(error).__name__,
                        "error": str(error),
                    }
                )
            )
            failures.append({"itemIdentifier": message_id})

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
    """AWS Lambda entry point for an SQS event source mapping."""
    request_id = "local-request"
    context_request_id = cast(
        object,
        getattr(context, "aws_request_id", None),
    )
    if isinstance(context_request_id, str) and context_request_id.strip():
        request_id = context_request_id

    return process_batch(event, request_id=request_id)
